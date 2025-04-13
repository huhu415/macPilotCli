# MacPilot CLI

MacPilot CLI is an open-source tool that enables Large Language Models (LLMs) to interact with macOS through the MCP (Model Control Protocol) protocol.
It provides a collection of system tools that allow AI assistants to perform various operations on macOS systems.

## Tool Documentation

| Tool Name | Description | Input Parameters |
|-----------|-------------|------------------|
| `getCursorPosition` | Get the current mouse position and screen details | None |
| `controlMouse` | Move the mouse to specified position and optionally click | `x`: X coordinate, `y`: Y coordinate, `click`: Boolean to click or not, `rightClick`: Boolean to right-click or not |
| `pasteText` | Copy text to clipboard and paste it | `text`: Text to paste |
| `captureScreen` | Take a screenshot of the entire screen and return image data | None |
| `shell` | Execute a shell command and return the output | `command`: Command to execute, `args`: Optional arguments array |
| `openApp` | Launch an application | `bundleId`: Application identifier or `appName`: Application name |
| `listApps` | Return a list of installed applications | None |
| `getWindowsInfo` | Return information about windows | `focusedOnly`: Boolean to get only focused window |
| `getWindowA11yInfo` | Return detailed accessibility information about a window | `pid`: Process ID, `windowNumber`: Window number |

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
