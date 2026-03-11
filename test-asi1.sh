#!/usr/bin/env bash
# Test the ASI1 API using the default test key from fetchcoder

API_KEY="sk_2a3c92a0b11e4f18b50708cca1a55179ab38a7c2fb7f4eee95fd68e1e28f860b"

echo "Testing ASI1 API with default fetchcoder test key..."
echo "Model: asi1-mini"
echo "---"

curl -s -w "\n\nHTTP Status: %{http_code}\n" \
  -X POST https://api.asi1.ai/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "asi1-mini",
    "messages": [
      {
        "role": "user",
        "content": "Say hello in one sentence."
      }
    ],
    "max_tokens": 100,
    "temperature": 0.7
  }'
