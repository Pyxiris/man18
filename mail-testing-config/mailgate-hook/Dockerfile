FROM docker.io/library/python:3.12-alpine

WORKDIR /app
COPY hook_server.py /app/hook_server.py
RUN chmod +x /app/hook_server.py

ENV PORT=8765
EXPOSE 8765

CMD ["python3", "/app/hook_server.py"]
