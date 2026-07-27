// Patched copy of dbee's output_buffer.go: raises bufio.Scanner's per-token
// limit from the default 64 KiB. Without this, Mongo documents with large
// string fields (e.g. stored SRT subtitles, ~33 KB, which render as a single
// ~112 KB table line) silently abort scanning and leave the result pane
// showing only the column header.
//
// Applied by the dbee.lua plugin spec's build step, which copies this over
// the plugin's source and rebuilds the binary with Go.
package handler

import (
	"bufio"
	"bytes"
	"fmt"

	"github.com/neovim/go-client/nvim"
)

func newBuffer(vim *nvim.Nvim, buffer nvim.Buffer) *Buffer {
	return &Buffer{
		buffer: buffer,
		vim:    vim,
	}
}

type Buffer struct {
	buffer nvim.Buffer
	vim    *nvim.Nvim
}

func (b *Buffer) Write(p []byte) (int, error) {
	scanner := bufio.NewScanner(bytes.NewReader(p))
	// Raise the per-token limit from the default 64 KiB. Mongo documents
	// with large string fields (e.g. stored subtitles) can render as a
	// single table line well above 64 KiB, which would silently abort
	// scanning and leave the result pane showing only the header.
	scanner.Buffer(make([]byte, 0, 64*1024), 16*1024*1024)
	var lines [][]byte
	for scanner.Scan() {
		lines = append(lines, []byte(scanner.Text()))
	}
	if err := scanner.Err(); err != nil {
		return 0, fmt.Errorf("buffer scan: %w", err)
	}

	const modifiableOptionName = "modifiable"

	// is the buffer modifiable
	isModifiable := false
	err := b.vim.BufferOption(b.buffer, modifiableOptionName, &isModifiable)
	if err != nil {
		return 0, err
	}

	if !isModifiable {
		err = b.vim.SetBufferOption(b.buffer, modifiableOptionName, true)
		if err != nil {
			return 0, err
		}
	}

	err = b.vim.SetBufferLines(b.buffer, 0, -1, true, lines)
	if err != nil {
		return 0, err
	}

	if !isModifiable {
		err = b.vim.SetBufferOption(b.buffer, modifiableOptionName, false)
		if err != nil {
			return 0, err
		}
	}

	return len(p), nil
}
