# Service A Dockerfile
FROM python:3.11

WORKDIR /app

COPY . .

RUN pip install -r requirements.txt

ENV SECRET_KEY=supersecret123
ENV DB_PASSWORD=admin1234

EXPOSE 5000

USER root

CMD ["python", "app.py"]
