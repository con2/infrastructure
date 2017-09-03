# pgAdmin4 management interface using the fenglc/pgadmin4 image

## Configuration

Apart from the standard vars, there is one called `pgadmin_container_links` that takes Docker links in the same format as `docker_container.links`. Use this to connect to Docker-based PostgreSQL servers. For examples, see the usage of `pgadmin4` role in `tracon.yml`.

## Manual steps

After setting up a new instance, log into it in the browser and set up the database server in pgAdmin4. You will need to create a PostgreSQL user for that. If you used a Docker link, use the link alias (likely `postgres`) as the DB hostname.
