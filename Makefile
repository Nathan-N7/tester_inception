COMPOSE = docker compose -f srcs/docker-compose.yml

all:
	mkdir -p /home/$(USER)/data/db
	mkdir -p /home/$(USER)/data/wordpress
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

re: down all

clean: down
	docker system prune -af
	sudo rm -rf /home/natrodri/data/db/*
	sudo rm -rf /home/natrodri/data/wordpress/*

fclean: clean
	docker volume prune -f

status:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f

.PHONY: all down re clean fclean status logs