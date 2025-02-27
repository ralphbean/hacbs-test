# Container image that runs your code
FROM docker.io/snyk/snyk:linux@sha256:c7f21c3d71f64d592e427e78d5043375c9b93e304f70fdbbd8ca7306cbb0ba1f as snyk
FROM quay.io/enterprise-contract/ec-cli:snapshot@sha256:141a7cd25ce0d098b1e40fd75d6f75873f8709c5f96f6340993b269c56e3f387 AS ec-cli
FROM gcr.io/projectsigstore/cosign:v1.13.6@sha256:366bf5a7e882e9748e2b05f620258f8eab89ef4e3597001279291a88486c4fdf as cosign-bin
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.3-1612

# Note that the version of OPA used by pr-checks must be updated manually to reflect conftest updates
# To find the OPA version associated with conftest run the following with the relevant version of conftest:
# $ conftest --version
ARG conftest_version=0.45.0
ARG BATS_VERSION=1.6.0
ARG sbom_utility_version=0.12.0
ARG OPM_VERSION=v1.26.3

ENV POLICY_PATH="/project"

RUN rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm && \
    microdnf -y --setopt=tsflags=nodocs --setopt=install_weak_deps=0 install \
    findutils \
    jq \
    skopeo \
    tar \
    python3 \
    clamav \
    clamd \
    python3-pip \
    clamav-update && \
    pip3 install --no-cache-dir yq && \
    curl -s -L https://github.com/CycloneDX/sbom-utility/releases/download/v"${sbom_utility_version}"/sbom-utility-v"${sbom_utility_version}"-linux-amd64.tar.gz --output sbom-utility.tar.gz && \
    mkdir sbom-utility && tar -xf sbom-utility.tar.gz -C sbom-utility && rm sbom-utility.tar.gz && \
    cd /usr/bin && \
    microdnf -y install libicu && \
    microdnf clean all

RUN ARCH=$(uname -m) && curl -s -L https://github.com/open-policy-agent/conftest/releases/download/v"${conftest_version}"/conftest_"${conftest_version}"_Linux_"$ARCH".tar.gz | tar -xz --no-same-owner -C /usr/bin/ && \
    curl https://mirror.openshift.com/pub/openshift-v4/"$ARCH"/clients/ocp/stable/openshift-client-linux.tar.gz --output oc.tar.gz && tar -xzvf oc.tar.gz -C /usr/bin && rm oc.tar.gz && \
    curl -s -LO "https://github.com/bats-core/bats-core/archive/refs/tags/v$BATS_VERSION.tar.gz" && \
    curl -s -L https://github.com/operator-framework/operator-registry/releases/download/"${OPM_VERSION}"/linux-amd64-opm > /usr/bin/opm && chmod +x /usr/bin/opm && \
    tar -xf "v$BATS_VERSION.tar.gz" && \
    cd "bats-core-$BATS_VERSION" && \
    ./install.sh /usr && \
    cd .. && rm -rf "bats-core-$BATS_VERSION" && rm -rf "v$BATS_VERSION.tar.gz" && \
    cd /

ENV PATH="${PATH}:/sbom-utility"

COPY --from=snyk /usr/local/bin/snyk /usr/local/bin/snyk

COPY --from=ec-cli /usr/bin/ec /usr/local/bin/ec

COPY --from=cosign-bin /ko-app/cosign /usr/local/bin/cosign


COPY policies $POLICY_PATH
COPY test/conftest.sh $POLICY_PATH

# Copies your code file from your action repository to the filesystem path `/` of the container
COPY test/selftest.sh /selftest.sh
COPY test/utils.sh /utils.sh

ENTRYPOINT ["/usr/bin/bash"]
