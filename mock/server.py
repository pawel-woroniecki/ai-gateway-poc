"""
Mock LLM Backend – symuluje endpoint OpenAI-compatible.
Strefa: local. Używany do testów bez kosztów API.
Zwraca deterministyczne odpowiedzi na podstawie promptu.
"""

import json
import time
import uuid
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

app = FastAPI(title="AI Gateway Mock Backend", version="0.1.0")

# --- Symulowane odpowiedzi ---

RESPONSES = {
    "default": "To jest odpowiedź z lokalnego mock backendu (strefa: local). "
               "Używam go do testów AI Gateway bez kosztów API.",
    "pii_test": "Jan Kowalski mieszka przy ul. Marszałkowskiej 10, Warszawa. "
                "Jego PESEL to 85010112345. Email: jan.kowalski@example.com",
    "secret_test": "Klucz API to sk-proj-abc123def456. "
                   "Token JWT: eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc",
    "long_response": "To jest dłuższa odpowiedź testowa. " * 50,
    "error_test": None,  # Triggeruje błąd 500
}


def detect_scenario(prompt: str) -> str:
    """Wykryj scenariusz testowy na podstawie treści promptu."""
    prompt_lower = prompt.lower()
    if "pesel" in prompt_lower or "dane osobowe" in prompt_lower or "pii" in prompt_lower:
        return "pii_test"
    if "secret" in prompt_lower or "api key" in prompt_lower or "token" in prompt_lower:
        return "secret_test"
    if "long" in prompt_lower or "długa odpowiedź" in prompt_lower:
        return "long_response"
    if "error" in prompt_lower or "błąd" in prompt_lower:
        return "error_test"
    return "default"


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    """Endpoint kompatybilny z OpenAI Chat Completions API."""
    try:
        body = await request.json()
    except json.JSONDecodeError:
        return JSONResponse(status_code=400, content={"error": "Invalid JSON"})

    messages = body.get("messages", [])
    model = body.get("model", "mock-local")

    # Ostatni user message jako prompt
    prompt = ""
    for msg in reversed(messages):
        if msg.get("role") == "user":
            prompt = msg.get("content", "")
            break

    scenario = detect_scenario(prompt)
    response_text = RESPONSES.get(scenario)

    # Scenariusz error_test – symuluj awarię
    if response_text is None:
        return JSONResponse(
            status_code=500,
            content={"error": {"message": "Mock: symulowany błąd serwera", "type": "server_error"}},
        )

    # Odpowiedź w formacie OpenAI
    completion_id = f"chatcmpl-mock-{uuid.uuid4().hex[:12]}"
    prompt_tokens = len(prompt.split()) * 2  # Przybliżenie
    completion_tokens = len(response_text.split()) * 2

    return JSONResponse(content={
        "id": completion_id,
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": response_text,
                },
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": prompt_tokens + completion_tokens,
        },
    })


@app.get("/health")
async def health():
    """Health check dla Kubernetes liveness/readiness probe."""
    return {"status": "ok", "zone": "local", "provider": "mock"}


@app.get("/v1/models")
async def list_models():
    """Lista dostępnych modeli – wymagane przez niektóre klienty."""
    return {
        "object": "list",
        "data": [
            {
                "id": "mock-local",
                "object": "model",
                "owned_by": "ai-gateway-poc",
                "metadata": {"zone": "local"},
            }
        ],
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
