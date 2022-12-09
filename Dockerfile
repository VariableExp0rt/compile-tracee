ARG TRACEE_RELEASE=0.6.4

FROM alpine:latest as builder
ARG TRACEE_RELEASE

SHELL [ "/bin/ash", "-eo", "pipefail", "-c" ]

WORKDIR /tmp
COPY ./build.sh build.sh
COPY ./rules/*.rego /tmp/rules/
RUN apk update && \
	apk --no-cache add \
    bash          \
    bc            \
    bison         \
    clang-dev     \
    clang-static  \
    cmake         \
    cpio          \
    dwarf-tools   \
    elfutils-dev  \
    flex          \
    gcc           \
    git           \
    go            \
    libelf-static \
    linux-headers \
    llvm          \
    llvm-static   \
    make          \
    musl-dev      \
    ncurses-dev   \
    openssl       \
    openssl-dev   \
    rpm2cpio      \
    sqlite        \
    zlib-static && \
    chmod +x build.sh && \
	./build.sh

FROM alpine:latest as runner

LABEL org.opencontainers.image.authors="@security"
LABEL org.opencontainers.image.channel="#infrastructure-security"
LABEL org.opencontainers.image.title="tracee"
LABEL org.opencontainers.image.type="alpine"
LABEL org.opencontainers.image.release_method="automatic"

ENV TINI_SUBREAPER=true
ENV TRACEE_EBPF_EXE=/app/tracee/tracee-ebpf
ENV TRACEE_RULES_EXE=/app/tracee/tracee-rules

COPY ./falcosidekick.tmpl ./rawjson.tmpl /app/tracee/templates/
COPY --from=builder /tmp/tracee/tracee-ebpf/dist/tracee-ebpf /tmp/tracee/tracee-rules/dist/tracee-rules /tmp/tracee/entrypoint.sh /app/tracee/
COPY --from=builder /tmp/tracee/tracee-rules/dist/rules /app/tracee/rules/
COPY --from=builder /tmp/tracee/tracee-ebpf/dist/tracee*.o /tmp/tracee/

RUN apk update && \
	apk --no-cache add \
	libc6-compat elfutils-dev \
	tini

ENTRYPOINT [ "/sbin/tini", "-g", "--", "/app/tracee/entrypoint.sh" ]
