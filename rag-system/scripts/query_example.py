from __future__ import annotations

import argparse
import json
from urllib import request


def main() -> None:
    parser = argparse.ArgumentParser(description="Example client for /query endpoint")
    parser.add_argument("question", help="Question to ask the RAG API")
    parser.add_argument("--api-url", default="http://127.0.0.1:8000", help="FastAPI base URL")
    parser.add_argument("--top-k", type=int, default=5, help="How many chunks to retrieve")
    args = parser.parse_args()

    payload = json.dumps({"question": args.question, "top_k": args.top_k}).encode("utf-8")
    req = request.Request(
        url=f"{args.api_url.rstrip('/')}/query",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    with request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))

    print("Answer:\n")
    print(data.get("answer", ""))
    print("\nSources:")
    for src in data.get("sources", []):
        print(f"- {src.get('source')} (page {src.get('page')}, score={src.get('score')})")


if __name__ == "__main__":
    main()
