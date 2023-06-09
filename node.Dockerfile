FROM alpine
RUN apk add --update jq py3-pip bash g++  && \
  wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | /bin/bash && \
  export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")" && \
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm && \
  TMP_LDFLAGS="$LDFLAGS" && \
  export LDFLAGS= && \
  nvm install -s 18