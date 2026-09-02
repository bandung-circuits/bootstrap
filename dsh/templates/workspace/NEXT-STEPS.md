# Next steps

Your AI workspace is ready at  ~/ai-workspace
One thing left: add your API key, then start the assistant.

## 1. Get an API key

Get a key for DeepSeek V4 Flash 0731 from {{PROVIDER_NAME}}:
  {{PROVIDER_SITE}}
(Full guide: https://bandung-circuits.github.io/bootstrap/providers-guide.html )

## 2. Add the key

If you gave one to the installer it is already saved in
  ~/ai-workspace/.dsh/.env   (line: DSH_API_KEY=...)

Otherwise open that file in any text editor and replace PASTE-YOUR-API-KEY-HERE.
You can also add it later inside the assistant itself:
  Settings -> Models -> (your provider) -> API key.

## 3. Start the assistant

Run (Linux/macOS):
  ~/ai-workspace/start-dsh.sh
or Windows:
  double-click start-dsh.cmd

Your browser opens DeepSeek Harness at  http://127.0.0.1:3080
Choose the workspace (this folder) and ask it anything, e.g.  "create a hello.py
and run it".

The crawl4ai MCP (web fetch/search) is already configured — no key needed.
If the assistant does not start, open a new terminal and run:  ~/ai-workspace/start-dsh.sh