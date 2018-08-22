FROM node:6
RUN groupadd -r slackirc && \
    useradd -r -g slackirc slackirc && \
    npm install --global slack-irc
USER slackirc
CMD ["slack-irc", "--config", "/slackirc.json"]
