//go:build windows

package ipc

import (
	"context"
	"fmt"
	"net"
	"os"
	"sync"
	"syscall"
	"unsafe"
)

var (
	modkernel32            = syscall.NewLazyDLL("kernel32.dll")
	procCreateNamedPipeW   = modkernel32.NewProc("CreateNamedPipeW")
	procConnectNamedPipe   = modkernel32.NewProc("ConnectNamedPipe")
	procDisconnectNamedPipe = modkernel32.NewProc("DisconnectNamedPipe")
)

const (
	PIPE_ACCESS_DUPLEX       = 0x00000003
	PIPE_TYPE_BYTE           = 0x00000000
	PIPE_READMODE_BYTE       = 0x00000000
	PIPE_WAIT                = 0x00000000
	PIPE_UNLIMITED_INSTANCES = 255
	BUFSIZE                  = 65536
)

type pipeConn struct {
	handle syscall.Handle
	file   *os.File
	once   sync.Once
}

func (c *pipeConn) Read(b []byte) (int, error) {
	return c.file.Read(b)
}

func (c *pipeConn) Write(b []byte) (int, error) {
	return c.file.Write(b)
}

func (c *pipeConn) Close() error {
	var err error
	c.once.Do(func() {
		procDisconnectNamedPipe.Call(uintptr(c.handle))
		err = c.file.Close()
	})
	return err
}

// StartListener starts the Windows Named Pipe listener loop.
func (s *Server) StartListener(ctx context.Context) error {
	pipeNameUTF16, err := syscall.UTF16PtrFromString(PipeName)
	if err != nil {
		return err
	}

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		handle, _, err := procCreateNamedPipeW.Call(
			uintptr(unsafe.Pointer(pipeNameUTF16)),
			uintptr(PIPE_ACCESS_DUPLEX),
			uintptr(PIPE_TYPE_BYTE|PIPE_READMODE_BYTE|PIPE_WAIT),
			uintptr(PIPE_UNLIMITED_INSTANCES),
			uintptr(BUFSIZE),
			uintptr(BUFSIZE),
			0,
			0,
		)

		if syscall.Handle(handle) == syscall.InvalidHandle {
			return fmt.Errorf("failed to create named pipe: %w", err)
		}

		// Wait for client connection
		r1, _, errConnect := procConnectNamedPipe.Call(handle, 0)
		if r1 == 0 {
			errno, ok := errConnect.(syscall.Errno)
			if !ok || errno != 0x217 { // ERROR_PIPE_CONNECTED (535)
				syscall.CloseHandle(syscall.Handle(handle))
				continue
			}
		}

		file := os.NewFile(uintptr(handle), PipeName)
		conn := &pipeConn{
			handle: syscall.Handle(handle),
			file:   file,
		}

		// Handle connection in current loop iteration or spawn goroutine for subsequent connections
		if err := s.HandleConnection(ctx, conn); err != nil {
			// Connection ended, loop around to recreate pipe instance
		}
	}
}
