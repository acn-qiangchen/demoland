# Apps

Each subdirectory is an independent demo application.

## Directory conventions

```
apps/<name>/
├── README.md          # What the demo does, how to run it locally
├── app.json           # Machine-readable metadata (CI/CD reads this)
├── Dockerfile         # Multi-stage container build
├── .dockerignore
└── src/               # Application source code
```

## Adding a new demo

```bash
./scripts/new-demo.sh <name>
```

This copies `_template/` and pre-fills `app.json`.

## Local development

```bash
# Build the container
docker build -t demoland/<name>:local apps/<name>

# Run it
docker run --rm -p 8080:8080 --env-file apps/<name>/.env.example demoland/<name>:local
```

The app will be available at http://localhost:8080.
