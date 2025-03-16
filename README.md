# MacPilot CLI

MacPilot CLI is an open-source tool that enables Large Language Models (LLMs) to interact with macOS through the MCP (Model Control Protocol) protocol.
It provides a collection of system tools that allow AI assistants to perform various operations on macOS systems.

## Tool Documentation

| Tool Name | Description | Input Parameters |
|-----------|-------------|------------------|
| `repeat` | Echo back the input text | `text`: String to repeat |
| `getCursorPosition` | Returns the current mouse position and screen details | None |
| `moveCursor` | Moves the mouse cursor to specific coordinates | `x`: X coordinate, `y`: Y coordinate |
| `clickMouse` | Performs a mouse click at the current cursor position | None |
| `pasteText` | Copies text to clipboard and pastes it | `text`: Text to paste |
| `captureScreen` | Takes a screenshot of the entire screen | None |
| `executeCommand` | Runs a shell command and returns the output | `command`: Command to execute, `args`: Optional arguments array |
| `launchApp` | Launches an application | `bundleId & Application identifier` or `appName & Application name` |
| `getAppsList` | Returns a list of installed applications | None |
| `getWindowsList` | Returns information about all windows | None |
| `getFocusedWindowInfo` | Returns information about the focused window | None |
| `getWindowInfo` | Returns detailed information about a window | `pid`: Optional process ID |

## Getting Started

1. You need a Mac computer with Apple Silicon running macOS 14.0 (Sonoma) or later
2. Download the binary file from the [Releases](https://github.com/huhu415/macPilotCli) section
3. Configure your MCP-compatible application (Cursor or Claude Desktop app) by adding the following configuration:
   ```json
   {
     "mcpServers": {
       "macPilotCli": {
         "command": "/path/to/downloaded/binary"
       }
     }
   }
   ```
4. Grant the necessary **permissions (screen recording, accessibility)** to the application you're using with MacPilot CLI.
*For example, if you're using Cursor, make sure Cursor has the required permissions in System Settings.*
5. Switch to a tool-compatible model according to your application's requirements, and you're ready to use MacPilot CLI
