FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    libx11-6 \
    libxcursor1 \
    libxrandr2 \
    libxinerama1 \
    libxi6 \
    libgl1 \
    libasound2 \
    libpulse0 \
    libfreetype6 \
    libssl3 \
    libnss3 \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy exported server binary
COPY export/linux_server/ ./

# Make executable
RUN chmod +x godot_server.x86_64

# Expose port (Render will override this)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD netstat -an | grep 8080 > /dev/null || exit 1

# Run server
CMD ["./godot_server.x86_64", "--headless"]
