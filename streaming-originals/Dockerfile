FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir flask requests
COPY engine.py app.py ./
COPY templates/ templates/
ENV DATA_DIR=/data
VOLUME /data
EXPOSE 7501
CMD ["python3", "app.py"]
