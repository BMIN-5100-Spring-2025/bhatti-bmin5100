FROM python:3.12
WORKDIR /app

COPY requirements.txt /app/requirements.txt

RUN pip install -r /app/requirements.txt

COPY app/ /app

CMD ["python3.12", "/app/inference.py"]
 