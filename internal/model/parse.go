package model

import (
	"bufio"
	"encoding/json"
	"io"
	"os"
)

// ParseSessionFile reads an entire JSONL session file and returns the parsed session.
func ParseSessionFile(path string) (*Session, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	session := &Session{}
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 64*1024)

	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) == 0 {
			continue
		}

		var base struct {
			Type      string `json:"type"`
			SessionID string `json:"session_id"`
		}
		if err := json.Unmarshal(line, &base); err != nil {
			continue // skip malformed lines
		}

		if session.ID == "" && base.SessionID != "" {
			session.ID = base.SessionID
		}

		switch base.Type {
		case "snapshot":
			var snap Snapshot
			if err := json.Unmarshal(line, &snap); err != nil {
				continue
			}
			session.Snapshots = append(session.Snapshots, snap)
			session.Latest = &session.Snapshots[len(session.Snapshots)-1]
			if session.StartedAt.IsZero() {
				session.StartedAt = snap.Timestamp
			}
		case "task_event":
			var evt TaskEvent
			if err := json.Unmarshal(line, &evt); err != nil {
				continue
			}
			session.TaskEvents = append(session.TaskEvents, evt)
		case "subagent_event":
			var evt SubagentEvent
			if err := json.Unmarshal(line, &evt); err != nil {
				continue
			}
			session.SubagentEvents = append(session.SubagentEvents, evt)
		}
	}

	return session, scanner.Err()
}

// ParseNewLines reads JSONL entries starting from a byte offset. Returns parsed data and the new offset.
func ParseNewLines(r io.ReadSeeker, offset int64) ([]Snapshot, []TaskEvent, []SubagentEvent, int64, error) {
	if _, err := r.Seek(offset, io.SeekStart); err != nil {
		return nil, nil, nil, offset, err
	}

	var snapshots []Snapshot
	var events []TaskEvent
	var subagents []SubagentEvent

	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 0, 64*1024), 64*1024)
	bytesRead := offset

	for scanner.Scan() {
		line := scanner.Bytes()
		bytesRead += int64(len(line)) + 1 // +1 for newline

		if len(line) == 0 {
			continue
		}

		var base struct {
			Type string `json:"type"`
		}
		if err := json.Unmarshal(line, &base); err != nil {
			continue
		}

		switch base.Type {
		case "snapshot":
			var snap Snapshot
			if err := json.Unmarshal(line, &snap); err != nil {
				continue
			}
			snapshots = append(snapshots, snap)
		case "task_event":
			var evt TaskEvent
			if err := json.Unmarshal(line, &evt); err != nil {
				continue
			}
			events = append(events, evt)
		case "subagent_event":
			var evt SubagentEvent
			if err := json.Unmarshal(line, &evt); err != nil {
				continue
			}
			subagents = append(subagents, evt)
		}
	}

	return snapshots, events, subagents, bytesRead, scanner.Err()
}
