# Service A Dockerfile
FROM python:3.11

WORKDIR /app

COPY . .

RUN pip install -r requirements.txt


EXPOSE 5000

USER root

CMD ["python", "app.py"]
