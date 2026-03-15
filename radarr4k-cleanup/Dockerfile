FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir flask requests

COPY app.py .
COPY templates/ templates/

EXPOSE 7500

CMD ["python3", "app.py"]