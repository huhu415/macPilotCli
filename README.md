# MacPilot CLI

MacPilot CLI is an open-source tool that enables Large Language Models (LLMs) to interact with macOS through the MCP (Model Control Protocol) protocol.
It provides a collection of system tools that allow AI assistants to perform various operations on macOS systems.

## Tool Documentation
  - `getCursorPosition`
  - `controlMouse`
  - `pasteText`
  - `captureScreen`
  - `shell`
  - `openApp`
  - `listApps`
  - `getWindowsInfo`
  - `getWindowA11yInfo`

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
