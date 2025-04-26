# Use an official Python image from Docker Hub
FROM python:3.11-slim

# Set the working directory inside the container
WORKDIR /app

# Copy requirements file first for separate dependency layer
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code
COPY . .

# Expose the Flask app's port
EXPOSE 5000

# Define environment variable for Flask
ENV FLASK_APP=app.py

# Start the Flask application
CMD ["flask", "run", "--host=0.0.0.0", "--port=5000"]
