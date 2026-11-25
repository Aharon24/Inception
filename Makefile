NAME = inception

COMPOSE = sudo docker compose --env-file srcs/.env -f srcs/docker-compose.yml

all: up

build:
	$(COMPOSE) build

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down --remove-orphans

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

clean:
	$(COMPOSE) down --remove-orphans

fclean:
	$(COMPOSE) down --rmi all --remove-orphans

re: fclean all

.PHONY: all build up down logs ps clean fclean re
