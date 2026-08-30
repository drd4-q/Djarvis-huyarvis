//go:build !windows

package ipc

import (
	"context"
	"fmt"
	"net"
	"os"
)

const UnixSocketPath = "/tmp/jarvis_ipc.sock"

// StartListener starts a Unix domain socket server for development/testing on non-Windows.
func (s *Server) StartListener(ctx context.Context) error {
	_ = os.Remove(UnixSocketPath)
	listener, err := net.Listen("unix", UnixSocketPath)
	if err != nil {
		return fmt.Errorf("failed to listen on unix socket: %w", err)
	}
	defer listener.Close()

	go func() {
		<-ctx.Done()
		listener.Close()
	}()

	for {
		conn, err := listener.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return ctx.Err()
			default:
				return err
			}
		}

		go func(c net.Conn) {
			_ = s.HandleConnection(ctx, c)
		}(conn)
	}
}
