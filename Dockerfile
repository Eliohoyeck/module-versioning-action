FROM node:16-alpine
LABEL "repository"="https://github.com/Eliohoyeck/module-versioning-action"
LABEL "homepage"="https://github.com/Eliohoyeck/module-versioning-action"
LABEL "maintainer"="Elio ELHOYECK"

RUN apk --no-cache add bash git curl jq && npm install -g semver

COPY versionning.sh /versionning.sh

ENTRYPOINT ["/versionning.sh"]
