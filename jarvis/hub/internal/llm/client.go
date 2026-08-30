package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

type Config struct {
	BaseURL     string        // e.g. "http://127.0.0.1:8080"
	ModelName   string        // e.g. "qwen2.5-3b-instruct"
	Timeout     time.Duration // HTTP request timeout
	Temperature float32
}

func DefaultConfig() Config {
	return Config{
		BaseURL:     "http://127.0.0.1:8080",
		ModelName:   "qwen2.5-3b-instruct",
		Timeout:     15 * time.Second,
		Temperature: 0.1,
	}
}

type Client struct {
	cfg        Config
	httpClient *http.Client
}

func NewClient(cfg Config) *Client {
	if cfg.Timeout == 0 {
		cfg.Timeout = 15 * time.Second
	}
	return &Client{
		cfg: cfg,
		httpClient: &http.Client{
			Timeout: cfg.Timeout,
		},
	}
}

// OpenAI-compatible Chat Completion Structures
type Message struct {
	Role       string     `json:"role"`
	Content    string     `json:"content,omitempty"`
	ToolCalls  []ToolCall `json:"tool_calls,omitempty"`
	ToolCallID string     `json:"tool_call_id,omitempty"`
}

type ToolCall struct {
	ID       string       `json:"id"`
	Type     string       `json:"type"` // "function"
	Function FunctionCall `json:"function"`
}

type FunctionCall struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"` // JSON string
}

type ToolDefinition struct {
	Type     string      `json:"type"` // "function"
	Function FunctionDef `json:"function"`
}

type FunctionDef struct {
	Name        string         `json:"name"`
	Description string         `json:"description"`
	Parameters  map[string]any `json:"parameters"`
}

type ChatRequest struct {
	Model       string           `json:"model"`
	Messages    []Message        `json:"messages"`
	Tools       []ToolDefinition `json:"tools,omitempty"`
	ToolChoice  any              `json:"tool_choice,omitempty"` // "auto"
	Temperature float32          `json:"temperature"`
	Stream      bool             `json:"stream"`
}

type ChatResponse struct {
	Choices []struct {
		Message      Message `json:"message"`
		FinishReason string  `json:"finish_reason"`
	} `json:"choices"`
	Usage struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
		TotalTokens      int `json:"total_tokens"`
	} `json:"usage"`
}

// GetToolsSchema returns the JSON tool schemas for Windows system actions.
func GetToolsSchema() []ToolDefinition {
	return []ToolDefinition{
		{
			Type: "function",
			Function: FunctionDef{
				Name:        "set_volume",
				Description: "Set system master audio volume or mute state on Windows.",
				Parameters: map[string]any{
					"type": "object",
					"properties": map[string]any{
						"level": map[string]any{
							"type":        "number",
							"description": "Volume scalar from 0.0 (silent) to 1.0 (100% max).",
							"minimum":     0.0,
							"maximum":     1.0,
						},
						"mute": map[string]any{
							"type":        "boolean",
							"description": "Optional mute flag (true to mute, false to unmute).",
						},
					},
					"required": []string{"level"},
				},
			},
		},
		{
			Type: "function",
			Function: FunctionDef{
				Name:        "lock_workstation",
				Description: "Immediately lock the Windows workstation / user session.",
				Parameters: map[string]any{
					"type":       "object",
					"properties": map[string]any{},
				},
			},
		},
		{
			Type: "function",
			Function: FunctionDef{
				Name:        "media_key",
				Description: "Send a multimedia hardware key event (play/pause, next track, previous track, volume up/down).",
				Parameters: map[string]any{
					"type": "object",
					"properties": map[string]any{
						"key": map[string]any{
							"type": "string",
							"enum": []string{"play_pause", "next", "prev", "vol_up", "vol_down", "mute"},
						},
					},
					"required": []string{"key"},
				},
			},
		},
		{
			Type: "function",
			Function: FunctionDef{
				Name:        "focus_window",
				Description: "Bring an active application window to the foreground by matching its title.",
				Parameters: map[string]any{
					"type": "object",
					"properties": map[string]any{
						"title_contains": map[string]any{
							"type":        "string",
							"description": "Substring of the window title to search and bring to front.",
						},
					},
					"required": []string{"title_contains"},
				},
			},
		},
		{
			Type: "function",
			Function: FunctionDef{
				Name:        "open_app",
				Description: "Launch or open a Windows application or executable.",
				Parameters: map[string]any{
					"type": "object",
					"properties": map[string]any{
						"path": map[string]any{
							"type":        "string",
							"description": "Executable name, full path, or shell URI (e.g. 'notepad', 'calc', 'msedge').",
						},
						"args": map[string]any{
							"type":        "string",
							"description": "Optional command line arguments.",
						},
					},
					"required": []string{"path"},
				},
			},
		},
	}
}

// SystemPrompt provides the instructions for Qwen2.5-3B.
const SystemPrompt = `Ты — Джарвис, высокоэффективный голосовой ИИ-ассистент для Windows.
Твоя задача — мгновенно выполнять команды пользователя или отвечать на вопросы кратко, вежливо и по делу.
Когда пользователь просит выполнить системное действие (изменить звук, переключить трек, заблокировать ПК, переключить окно, запустить программу), ты ОБЯЗАН использовать соответствующий вызов инструмента (tool_call).
Отвечай на русском языке кратко (1-2 предложения), без лишней воды.`

func (c *Client) Complete(ctx context.Context, history []Message) (*Message, error) {
	reqBody := ChatRequest{
		Model:       c.cfg.ModelName,
		Messages:    history,
		Tools:       GetToolsSchema(),
		ToolChoice:  "auto",
		Temperature: c.cfg.Temperature,
		Stream:      false,
	}

	rawJSON, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	reqURL := fmt.Sprintf("%s/v1/chat/completions", c.cfg.BaseURL)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, reqURL, bytes.NewReader(rawJSON))
	if err != nil {
		return nil, fmt.Errorf("failed to create http request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("llama-server request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("llama-server returned status %d: %s", resp.StatusCode, string(body))
	}

	var chatResp ChatResponse
	if err := json.NewDecoder(resp.Body).Decode(&chatResp); err != nil {
		return nil, fmt.Errorf("failed to decode llama-server response: %w", err)
	}

	if len(chatResp.Choices) == 0 {
		return nil, errors.New("llama-server returned no choices")
	}

	return &chatResp.Choices[0].Message, nil
}
