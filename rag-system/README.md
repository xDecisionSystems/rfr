# Research RAG System (Azure OpenAI + Native Qdrant, No Docker)

## 1) Debian/LXC setup

```bash
cd rag-system
sudo ./setup.sh
```

## 2) Install and run Qdrant natively

```bash
sudo ./install_qdrant.sh
/opt/qdrant/qdrant
```

`install_qdrant.sh` creates `/opt/qdrant/storage` and aligns ownership to `raguser` when that user exists.

Optional systemd service:

```bash
sudo cp deploy/qdrant.service /etc/systemd/system/qdrant.service
sudo systemctl daemon-reload
sudo systemctl enable --now qdrant
```

## 3) Python environment

If you already ran `setup.sh`, `/opt/rag-env` is already created and dependencies are installed.

```bash
python3 -m venv /opt/rag-env
source /opt/rag-env/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

## 4) Configure Azure OpenAI

```bash
cp .env.example .env
# edit .env with your Azure endpoint/key/deployment names
```

Required keys:

- `AZURE_OPENAI_ENDPOINT`
- `AZURE_OPENAI_API_KEY`
- `EMBEDDING_DEPLOYMENT_NAME`
- `CHAT_DEPLOYMENT_NAME`

## 5) Ingest papers

Put PDFs in `data/papers/`, then ingest:

```bash
source /opt/rag-env/bin/activate
python scripts/ingest_folder.py data/papers
```

Or via API endpoint `/ingest`.

## 6) Run API

```bash
source /opt/rag-env/bin/activate
uvicorn api.main:app --host 0.0.0.0 --port 8000
```

## 7) Query

```bash
python scripts/query_example.py "What is the main contribution?"
```

Or call API `/query` with JSON:

```json
{
  "question": "...",
  "top_k": 5
}
```
