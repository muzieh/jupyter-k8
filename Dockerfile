# JupyterLab image for archi: the upstream scipy-notebook plus the packages
# in requirements.txt. A push to main builds it and Argo CD deploys it, see
# README.md.
#
# The base tag is pinned by date. Raising it is a visible change in git, and
# a new Python version means packages in ~/.local (from `%pip install` in a
# notebook) must be installed again.
FROM quay.io/jupyter/scipy-notebook:2026-09-29

# The base image already runs as jovyan (uid 1000) and jovyan owns /opt/conda,
# so no USER switch is needed. Packages land in /opt/conda, inside the image.
COPY --chown=1000:100 requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
 && rm /tmp/requirements.txt

# Smoke test: a package that does not import fails the build, so a broken
# image never reaches the registry.
RUN python -c "import openai, dotenv; print('openai', openai.__version__)"
