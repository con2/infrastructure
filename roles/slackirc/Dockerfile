FROM node:6
RUN groupadd -r slackirc && \
    useradd -r -g slackirc slackirc && \
    git clone --branch entities-handling https://github.com/jlaunonen/slack-irc.git /usr/src/app && \
    cd /usr/src/app && \
    npm install && \
    npm run build
USER slackirc
CMD ["node", "/usr/src/app/dist/index.js", "--config", "/slackirc.json"]
