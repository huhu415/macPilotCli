build:
	swift build

resolve:
	swift package resolve

mcpDebug:
	npx @modelcontextprotocol/inspector /Users/hello/projects/macPilotCli/.build/debug/macPilotCli

stream:
	log stream --predicate 'category == "mcp"' --info --debug

format:
	swiftformat .
