# PDF Processor Infrastructure

## Overview

PDF Processor Infrastructure is the Docker Compose deployment layer for the PDF Processor application. It brings the prebuilt web and backend services together with a local large language model runtime and a vector database, providing one reproducible way to run the complete system.

The repository solves the operational problem of starting these dependent services in the correct order and connecting them on a shared network. It also persists model and vector data on the host, prepares the configured Ollama model before the backend starts, and supports custom certificate authorities for networks that inspect outbound TLS traffic.

Application source code is not included here. The frontend and backend are distributed as container images from GitHub Container Registry (GHCR).

## Features

- Runs the frontend, backend, Qdrant, and Ollama as one Compose application.
- Downloads the configured Ollama model during startup and gates backend startup on successful completion.
- Persists Qdrant storage and downloaded Ollama models in configurable host directories.
- Uses an isolated Docker bridge network for service-to-service communication.
- Exposes the web application, backend, Qdrant, and Ollama on their standard host ports.
- Supports custom `.crt` and `.pem` certificate authorities for the model download process.
- Restarts long-running services automatically unless they are explicitly stopped.
- Provides a setup script for generating host volume settings in `.env`.
- Includes a GitHub Actions workflow for VPN-based deployment to the configured remote host.

## Architecture

The browser-facing frontend calls the backend, while the backend communicates with Ollama for model inference and Qdrant for vector storage. All containers share the `pdf-network` bridge network. Qdrant and Ollama bind-mount host directories so their state survives container replacement.

```text
                         pdf-network

Browser                 +--------------------+
   |                     |                    |
   | :3000               v                    v
   +----------> [ Frontend ] -----> [ Backend :8000 ]
                                          |       |
                                          |       |
                                          v       v
                                  [ Ollama ]   [ Qdrant ]
                                     :11434    :6333/:6334
                                      ^            |
                                      |            |
                               [ ollama-pull ]      |
                                      |            |
                                host model     host vector
                                  storage        storage
```

`ollama-pull` is a one-shot initialization service. It waits for Ollama to become healthy, downloads `OLLAMA_MODEL`, and exits. The backend starts only after that job succeeds and Ollama is healthy.

## How It Works

1. Docker Compose creates the `pdf-network` bridge network and starts Qdrant and Ollama.
2. Ollama serves its API on port `11434`. Its health check repeatedly runs `ollama list` until the service is ready.
3. Once Ollama is healthy, `ollama-pull` downloads the model selected by `OLLAMA_MODEL` into the shared Ollama data directory.
4. The backend starts after Qdrant has started, Ollama is healthy, and the model pull has completed successfully.
5. The frontend starts with the backend as a Compose dependency and is published at `http://localhost:3000`.
6. Requests flow from the frontend to the backend. The backend reaches Ollama and Qdrant through their internal Compose DNS names.

Startup time and disk use are dominated by the selected model download. No application algorithms are implemented in this repository, so algorithmic complexity is determined by the separately distributed frontend, backend, model, and database images.

## Technologies Used

### Application Services

- **Frontend:** Prebuilt `ghcr.io/relewant-dev/pdf-processor-app:latest` image, configured for production on port `3000`.
- **Backend:** Prebuilt `ghcr.io/relewant-dev/pdf-processor-services:latest` image on port `8000`.

### Data and AI Services

- **Qdrant:** Vector database with HTTP and gRPC ports `6333` and `6334`.
- **Ollama 0.24.0:** CPU-configured local model runtime. The default model is `llama3.1:8b`.

### Deployment

- **Docker Compose:** Service orchestration, health checks, networking, volumes, and restart policies.
- **GitHub Container Registry:** Distribution of the frontend and backend images.
- **GitHub Actions:** Remote deployment triggered manually or by frontend/backend repository dispatch events.
- **WireGuard and SSH:** Connectivity and remote execution in the deployment workflow.

### Automation

- **Bash and `awk`:** Idempotent generation and updating of local volume configuration.

## Project Structure

```text
.
├── .github/
│   └── workflows/
│       └── ci.yaml                 # VPN-based remote deployment workflow
├── backend/
│   └── .env                        # Environment file loaded by the backend container
├── scripts/
│   └── setup-docker-volumes.sh     # Creates or updates root volume configuration
├── .env.example                    # Example Compose environment values
├── .gitignore
├── docker-compose.yml              # Complete multi-container topology
├── LICENSE                         # MIT License
└── README.md
```

## Installation

### Prerequisites

- Docker Engine with the Compose plugin (`docker compose`)
- Access to the two application images in `ghcr.io/relewant-dev`
- Sufficient disk space for the selected Ollama model and Qdrant data
- Write access to the configured host storage directories
- A populated `backend/.env` file for the backend image

### Configure the environment

Copy the example configuration and adjust it for your host:

```bash
cp .env.example .env
```

The supported Compose settings are:

| Variable | Default | Purpose |
| --- | --- | --- |
| `QDRANT_STORAGE_DIR` | `/home/administrator/data/qdrant/storage` | Host directory for Qdrant data |
| `OLLAMA_DATA_DIR` | `/home/administrator/data/ollama` | Host directory for models and Ollama state |
| `OLLAMA_CA_CERTS_DIR` | `./certs/ollama` | Read-only directory containing optional custom CA files |
| `OLLAMA_MODEL` | `llama3.1:8b` | Model downloaded before backend startup |

Create the required host directories before starting the stack. For example:

```bash
mkdir -p /opt/pdf-processor/qdrant \
  /opt/pdf-processor/ollama \
  /opt/pdf-processor/certs/ollama
```

Alternatively, generate `.env` with the included script:

```bash
bash scripts/setup-docker-volumes.sh \
  /opt/pdf-processor/qdrant \
  /opt/pdf-processor/ollama
```

The script backs up an existing `.env` as `.env.bak`. If no arguments are supplied, it writes the repository defaults. Configure `OLLAMA_CA_CERTS_DIR` and `OLLAMA_MODEL` directly in `.env` when their defaults are not suitable.

If a registry login is required, authenticate before pulling the application images:

```bash
docker login ghcr.io
```

## Running Locally

Start the entire stack in the background:

```bash
docker compose up -d
```

The initial run may take time while Ollama downloads the configured model. Follow initialization and service logs with:

```bash
docker compose logs -f ollama ollama-pull backend frontend
```

Inspect service state:

```bash
docker compose ps
```

Once the containers are ready, the published interfaces are:

| Component | Local address |
| --- | --- |
| Frontend | `http://localhost:3000` |
| Backend | `http://localhost:8000` |
| Qdrant HTTP | `http://localhost:6333` |
| Qdrant gRPC | `localhost:6334` |
| Ollama | `http://localhost:11434` |

Stop and remove the containers and network with:

```bash
docker compose down
```

The bind-mounted Qdrant and Ollama data remains on the host after shutdown.

### Custom certificate authorities

If model retrieval fails with `x509: certificate signed by unknown authority`, place the required `.crt` or `.pem` files in `OLLAMA_CA_CERTS_DIR`, then run the stack again. That directory is mounted read-only into the model initialization container.

## API Documentation

This infrastructure repository publishes the backend on port `8000`, but it does not contain the backend implementation or an API specification. Endpoint paths, request schemas, and response schemas must therefore be obtained from the `pdf-processor-services` project or its running image; documenting them here would risk diverging from the deployed version.

The infrastructure-level service URLs are configured as follows:

```text
Frontend -> backend:  http://backend:8000
Backend  -> Ollama:   http://ollama:11434
Backend  -> Qdrant:   http://qdrant:6333
```

## Implementation Details

### Deterministic startup ordering

Compose dependency conditions prevent the backend from starting before its runtime dependencies are usable. Ollama has an explicit health check, and `ollama-pull` must exit successfully. This separates long-running model serving from one-time model preparation while allowing both containers to share the same persisted model directory.

### Host-managed persistence

Bind mounts make storage locations explicit and configurable for the deployment host. This is useful when model and vector data must live on dedicated disks or outside Docker-managed volumes. Parameter expansion in `docker-compose.yml` provides working defaults while allowing `.env` or shell variables to override them.

### CPU-oriented Ollama configuration

The Compose definition disables Vulkan and flash attention and selects the CPU library. This makes the declared deployment independent of GPU runtime configuration, while model performance remains dependent on the host CPU, memory, and selected model.

### Automated deployment

The GitHub Actions workflow can run manually or respond to `backend-deployed` and `frontend-deployed` repository dispatch events. It connects to the target network through WireGuard, authenticates with GHCR on the remote server, updates the `main` branch, pulls the images, and recreates the Compose stack. Its host address and required credentials are deployment-specific and supplied through repository secrets where configured.

## Performance

- **Model initialization:** The model is downloaded once into persistent storage. Subsequent container recreations reuse that storage, although `ollama-pull` still verifies the requested model through the `ollama pull` command.
- **Service isolation:** Backend-to-database and backend-to-model traffic remains on the Docker bridge network rather than traversing published host ports.
- **Persistence:** Bind mounts avoid losing large model artifacts or vector data when containers are replaced.
- **Scaling:** The Compose file declares one instance of each service and uses fixed container names and host ports. Horizontal scaling and load balancing are not configured.
- **Inference:** Ollama is explicitly configured for CPU execution. Throughput and latency depend on the host hardware and selected model.

## Future Improvements

Potential infrastructure work, without implying current support, includes:

- Pinning all container images to immutable versions or digests for reproducible deployments.
- Adding automated Compose validation and service smoke tests to continuous integration.
- Adding resource limits and documented capacity guidance for Ollama and Qdrant.
- Providing deployment profiles for alternative hardware configurations.
- Publishing or linking a versioned backend API specification.

## License

This project is available under the [MIT License](LICENSE).
