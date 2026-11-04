FROM python:3.13-slim@sha256:ae14d4ce8771606477a81446e7ef429edd6762305fc50c84507c1041fa8285d1 AS model
COPY download_model.py /download_model.py
RUN python /download_model.py

FROM ghcr.io/ggml-org/llama.cpp:server@sha256:ba68b6996ba6d27a49a9864452194128e118a1fcb96dd663f223a13e0a2857a8
COPY --from=model /model /model
ENV HOME=/tmp
USER 1000:1000
EXPOSE 7860
CMD ["--model", "/model/model.gguf", "--host", "0.0.0.0", "--port", "7860", "--ctx-size", "4096", "--parallel", "1", "--threads", "2", "--no-webui", "--log-disable"]
