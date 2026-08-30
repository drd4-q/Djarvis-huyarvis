package router

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"jarvis/hub/internal/ipc"
	"jarvis/hub/internal/llm"
)

type Router struct {
	ipcServer *ipc.Server
	llmClient *llm.Client
	
	mu       sync.Mutex
	history  []llm.Message
	maxTurns int
}

func NewRouter(ipcServer *ipc.Server, llmClient *llm.Client) *Router {
	r := &Router{
		ipcServer: ipcServer,
		llmClient: llmClient,
		maxTurns:  10,
	}
	r.resetHistory()
	return r
}

func (r *Router) resetHistory() {
	r.history = []llm.Message{
		{
			Role:    "system",
			Content: llm.SystemPrompt,
		},
	}
}

// ProcessUserText handles text input from STT or user interface and executes LLM orchestrations.
func (r *Router) ProcessUserText(ctx context.Context, text string) (string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	log.Printf("[Router] User input: %q\n", text)
	r.history = append(r.history, llm.Message{
		Role:    "user",
		Content: text,
	})

	// Request LLM completion
	msg, err := r.llmClient.Complete(ctx, r.history)
	if err != nil {
		return "", fmt.Errorf("llm completion error: %w", err)
	}

	r.history = append(r.history, *msg)

	// Check if LLM emitted any tool calls
	if len(msg.ToolCalls) > 0 {
		for _, tc := range msg.ToolCalls {
			log.Printf("[Router] Executing tool call: %s with args: %s\n", tc.Function.Name, tc.Function.Arguments)
			
			var params map[string]any
			if tc.Function.Arguments != "" {
				_ = json.Unmarshal([]byte(tc.Function.Arguments), &params)
			}

			// Send to native Zig core via IPC
			res, err := r.ipcServer.SendAction(ctx, tc.Function.Name, params, 3*time.Second)
			actionStatus := "ok"
			if err != nil {
				actionStatus = fmt.Sprintf("error: %v", err)
				log.Printf("[Router] Action %s failed: %v\n", tc.Function.Name, err)
			} else if res.Status != "ok" {
				actionStatus = fmt.Sprintf("error: %s", res.Error)
				log.Printf("[Router] Native core reported error for %s: %s\n", tc.Function.Name, res.Error)
			} else {
				log.Printf("[Router] Action %s executed successfully\n", tc.Function.Name)
			}

			// Feed tool result back to LLM context
			r.history = append(r.history, llm.Message{
				Role:       "tool",
				Content:    actionStatus,
				ToolCallID: tc.ID,
			})
		}

		// Get final conversational reply after tool execution
		finalMsg, err := r.llmClient.Complete(ctx, r.history)
		if err == nil && finalMsg.Content != "" {
			r.history = append(r.history, *finalMsg)
			r.pruneHistory()
			return finalMsg.Content, nil
		}
	}

	r.pruneHistory()
	return msg.Content, nil
}

func (r *Router) pruneHistory() {
	if len(r.history) > (r.maxTurns*2 + 1) {
		// Keep system prompt + last N messages
		keepFrom := len(r.history) - (r.maxTurns * 2)
		r.history = append([]llm.Message{r.history[0]}, r.history[keepFrom:]...)
	}
}
