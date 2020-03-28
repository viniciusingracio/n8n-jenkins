# psql-k8s

Docker image to connect with psql in a Postgres running in kubernetes.

## How to

Edit `.env.local` and add your `DO_KEY`.

Build the image:

```
docker build . -t psql-k8s -f Dockerfile.psql-k8s
```

Run the image:

```
docker run -ti --rm -v `pwd`/.env.local:/usr/src/app/.env psql-k8s
```

To run a single query:

```
docker run -ti --rm -v `pwd`/.env.local:/usr/src/app/.env psql-k8s -c 'SELECT name FROM servers;'
```
