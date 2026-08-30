package ipc

import (
	"encoding/binary"
	"errors"
	"io"
)

// Magic bytes for frame synchronization ('J', 'V')
const Magic uint16 = 0x4A56

// Message types
const (
	MsgPing           uint16 = 0x0001
	MsgPong           uint16 = 0x0002
	MsgAudioInChunk   uint16 = 0x0010 // PCM 16kHz 16-bit mono from Zig -> Go
	MsgAudioOutChunk  uint16 = 0x0011 // PCM 24kHz 16-bit mono from Go -> Zig
	MsgAudioOutStop   uint16 = 0x0012 // Signal to flush/stop playback buffer
	MsgExecAction     uint16 = 0x0020 // Go -> Zig (JSON)
	MsgActionResult   uint16 = 0x0021 // Zig -> Go (JSON)
	MsgSystemEvent    uint16 = 0x0030 // Zig -> Go (JSON)
)

const HeaderSize = 8
const MaxPayloadSize = 4 * 1024 * 1024 // 4 MB safety limit

var (
	ErrInvalidMagic   = errors.New("ipc: invalid magic bytes")
	ErrPayloadTooLarge = errors.New("ipc: payload exceeds max size")
)

// Header represents the 8-byte binary frame header
type Header struct {
	Magic      uint16
	MsgType    uint16
	PayloadLen uint32
}

// Packet represents a full IPC frame
type Packet struct {
	Type    uint16
	Payload []byte
}

// ActionCommand represents an action sent to the native core
type ActionCommand struct {
	ID     string         `json:"id"`
	Action string         `json:"action"`
	Params map[string]any `json:"params,omitempty"`
}

// ActionResult represents the execution status sent back from native core
type ActionResult struct {
	ID     string `json:"id"`
	Status string `json:"status"` // "ok" | "error"
	Error  string `json:"error,omitempty"`
}

// SystemEvent represents an asynchronous event from native core
type SystemEvent struct {
	Event string         `json:"event"`
	Data  map[string]any `json:"data,omitempty"`
}

// ReadPacket reads a single framed packet from the stream.
func ReadPacket(r io.Reader) (*Packet, error) {
	var headerBuf [HeaderSize]byte
	if _, err := io.ReadFull(r, headerBuf[:]); err != nil {
		return nil, err
	}

	magic := binary.LittleEndian.Uint16(headerBuf[0:2])
	if magic != Magic {
		return nil, ErrInvalidMagic
	}

	msgType := binary.LittleEndian.Uint16(headerBuf[2:4])
	payloadLen := binary.LittleEndian.Uint32(headerBuf[4:8])

	if payloadLen > MaxPayloadSize {
		return nil, ErrPayloadTooLarge
	}

	payload := make([]byte, payloadLen)
	if payloadLen > 0 {
		if _, err := io.ReadFull(r, payload); err != nil {
			return nil, err
		}
	}

	return &Packet{
		Type:    msgType,
		Payload: payload,
	}, nil
}

// WritePacket writes a framed packet to the stream.
func WritePacket(w io.Writer, msgType uint16, payload []byte) error {
	payloadLen := uint32(len(payload))
	if payloadLen > MaxPayloadSize {
		return ErrPayloadTooLarge
	}

	var headerBuf [HeaderSize]byte
	binary.LittleEndian.PutUint16(headerBuf[0:2], Magic)
	binary.LittleEndian.PutUint16(headerBuf[2:4], msgType)
	binary.LittleEndian.PutUint32(headerBuf[4:8], payloadLen)

	if _, err := w.Write(headerBuf[:]); err != nil {
		return err
	}

	if payloadLen > 0 {
		if _, err := w.Write(payload); err != nil {
			return err
		}
	}

	return nil
}
