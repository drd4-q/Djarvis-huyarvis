package main

import (
	"bufio"
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"jarvis/hub/internal/ipc"
	"jarvis/hub/internal/llm"
	"jarvis/hub/internal/router"
)

func main() {
	log.Println("==================================================")
	log.Println(" Jarvis AI Hub (Control & Orchestration Layer)")
	log.Println("==================================================")

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle graceful shutdown signals
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigChan
		log.Println("\n[Hub] Shutting down...")
		cancel()
	}()

	// 1. Initialize IPC Server
	ipcServer := ipc.NewServer()

	// 2. Initialize LLM Client (pointing to llama-server)
	llmCfg := llm.DefaultConfig()
	if envURL := os.Getenv("LLAMA_SERVER_URL"); envURL != "" {
		llmCfg.BaseURL = envURL
	}
	llmClient := llm.NewClient(llmCfg)

	// 3. Initialize Router
	hubRouter := router.NewRouter(ipcServer, llmClient)

	// 4. Start Named Pipe Listener in background
	go func() {
		log.Printf("[Hub] Starting IPC listener on %s...\n", ipc.PipeName)
		if err := ipcServer.StartListener(ctx); err != nil && ctx.Err() == nil {
			log.Fatalf("[Hub] IPC listener error: %v\n", err)
		}
	}()

	// 5. Background loop for handling asynchronous system events from Zig core
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case ev := <-ipcServer.EventChan:
				log.Printf("[Hub] System event received: %+v\n", ev)
			}
		}
	}()

	// 6. Background loop for consuming incoming audio chunks
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case chunk := <-ipcServer.AudioInChan:
				// Forward to STT / VAD engine (e.g. whisper.cpp / silero)
				_ = chunk
			}
		}
	}()

	// 7. Interactive CLI loop for testing text commands directly
	log.Println("[Hub] Ready. Type your command in console or speak via microphone.")
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		if line == "exit" || line == "quit" {
			break
		}

		reply, err := hubRouter.ProcessUserText(ctx, line)
		if err != nil {
			log.Printf("[Hub] Error processing request: %v\n", err)
		} else {
			fmt.Printf("[Jarvis]: %s\n", reply)
		}
	}
}
