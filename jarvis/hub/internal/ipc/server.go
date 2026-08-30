package ipc

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"sync"
	"sync/atomic"
	"time"
)

const PipeName = `\\.\pipe\jarvis_ipc`

// Server manages communication with the native Zig client.
type Server struct {
	mu           sync.Mutex
	activeConn   io.ReadWriteCloser
	writeMu      sync.Mutex
	isClosed     atomic.Bool
	
	// Channels for routing incoming messages to hub subsystems
	AudioInChan  chan []byte
	ResultChan   chan ActionResult
	EventChan    chan SystemEvent

	// Pending action response waiting map (id -> chan ActionResult)
	pendingMu sync.Mutex
	pending   map[string]chan ActionResult
}

// NewServer creates a new IPC server instance.
func NewServer() *Server {
	return &Server{
		AudioInChan: make(chan []byte, 128),
		ResultChan:  make(chan ActionResult, 32),
		EventChan:   make(chan SystemEvent, 32),
		pending:     make(map[string]chan ActionResult),
	}
}

// SetConnection sets the current active connection and starts the message handling loop.
func (s *Server) HandleConnection(ctx context.Context, conn io.ReadWriteCloser) error {
	s.mu.Lock()
	if s.activeConn != nil {
		s.activeConn.Close()
	}
	s.activeConn = conn
	s.mu.Unlock()

	log.Println("[IPC] Native Zig core connected")

	defer func() {
		s.mu.Lock()
		if s.activeConn == conn {
			s.activeConn = nil
		}
		s.mu.Unlock()
		conn.Close()
		log.Println("[IPC] Native Zig core disconnected")
	}()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		packet, err := ReadPacket(conn)
		if err != nil {
			if errors.Is(err, io.EOF) || errors.Is(err, io.ErrClosedPipe) {
				return nil
			}
			return fmt.Errorf("read packet error: %w", err)
		}

		s.dispatchPacket(conn, packet)
	}
}

func (s *Server) dispatchPacket(conn io.Writer, pkt *Packet) {
	switch pkt.Type {
	case MsgPing:
		// Respond with Pong immediately
		_ = s.sendRaw(conn, MsgPong, nil)

	case MsgPong:
		// Heartbeat ack

	case MsgAudioInChunk:
		// Non-blocking write to audio channel, drop if overwhelmed to maintain low latency
		select {
		case s.AudioInChan <- pkt.Payload:
		default:
			// Buffer full, drop oldest or current packet to prevent blocking real-time loop
		}

	case MsgActionResult:
		var res ActionResult
		if err := json.Unmarshal(pkt.Payload, &res); err == nil {
			s.pendingMu.Lock()
			ch, exists := s.pending[res.ID]
			if exists {
				delete(s.pending, res.ID)
				s.pendingMu.Unlock()
				select {
				case ch <- res:
				default:
				}
			} else {
				s.pendingMu.Unlock()
			}

			select {
			case s.ResultChan <- res:
			default:
			}
		}

	case MsgSystemEvent:
		var ev SystemEvent
		if err := json.Unmarshal(pkt.Payload, &ev); err == nil {
			select {
			case s.EventChan <- ev:
			default:
			}
		}

	default:
		log.Printf("[IPC] Unknown message type received: 0x%04X\n", pkt.Type)
	}
}

func (s *Server) sendRaw(w io.Writer, msgType uint16, payload []byte) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	return WritePacket(w, msgType, payload)
}

// SendAction sends a command to the Zig core and waits for a response with a timeout.
func (s *Server) SendAction(ctx context.Context, action string, params map[string]any, timeout time.Duration) (*ActionResult, error) {
	s.mu.Lock()
	conn := s.activeConn
	s.mu.Unlock()

	if conn == nil {
		return nil, errors.New("ipc: native client is not connected")
	}

	reqID := fmt.Sprintf("act-%d", time.Now().UnixNano())
	cmd := ActionCommand{
		ID:     reqID,
		Action: action,
		Params: params,
	}

	payload, err := json.Marshal(cmd)
	if err != nil {
		return nil, err
	}

	respChan := make(chan ActionResult, 1)
	s.pendingMu.Lock()
	s.pending[reqID] = respChan
	s.pendingMu.Unlock()

	defer func() {
		s.pendingMu.Lock()
		delete(s.pending, reqID)
		s.pendingMu.Unlock()
	}()

	if err := s.sendRaw(conn, MsgExecAction, payload); err != nil {
		return nil, fmt.Errorf("failed to send action: %w", err)
	}

	tctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	select {
	case res := <-respChan:
		return &res, nil
	case <-tctx.Done():
		return nil, errors.New("ipc: action timed out waiting for native response")
	}
}

// SendAudioOut streams synthesized PCM audio chunks to Zig for playback.
func (s *Server) SendAudioOut(chunk []byte) error {
	s.mu.Lock()
	conn := s.activeConn
	s.mu.Unlock()

	if conn == nil {
		return errors.New("ipc: native client is not connected")
	}

	return s.sendRaw(conn, MsgAudioOutChunk, chunk)
}

// StopAudioOut sends an immediate interrupt to stop current playback.
func (s *Server) StopAudioOut() error {
	s.mu.Lock()
	conn := s.activeConn
	s.mu.Unlock()

	if conn == nil {
		return nil
	}

	return s.sendRaw(conn, MsgAudioOutStop, nil)
}
