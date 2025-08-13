# ElixirFastCharge

A distributed Elixir application for managing electric vehicle charging stations with features like user management, station monitoring, shift scheduling, and pre-reservations.

## Prerequisites

- Elixir ~> 1.18
- Mix (Elixir's build tool)

## Installation

1. Clone the repository
2. Install dependencies:
```bash
mix deps.get
mix deps.compile
```

## Running the Distributed System

The application is designed to run as a distributed system with multiple nodes. Each node needs to be started with a unique name and port.

### Starting the Nodes

Open different terminal windows for each node you want to start. Here's how to start two nodes:

#### Node 1 (Primary)
```bash
PORT=4001 iex --name node1@127.0.0.1 -S mix
```

#### Node 2
```bash
PORT=4002 iex --name node2@127.0.0.1 -S mix
```

### Port Configuration

Each node runs two services:
- Main HTTP API: Uses the specified PORT (e.g., 4001, 4002)
- Prometheus Metrics: Automatically uses PORT + 5000 (e.g., 9001, 9002)

### Node Discovery

The nodes will automatically discover each other using libcluster. The configured nodes are:
- node1@127.0.0.1
- node2@127.0.0.1

## Architecture

The application uses:
- Horde for distributed Registry and Supervisor
- Plug.Cowboy for HTTP API
- Libcluster for node discovery and clustering
- Prometheus for metrics collection
- ETS tables for distributed data replication
- Monitors for certain data replication

## API Endpoints

