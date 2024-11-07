# create an image that includes the entire build context
docker build -t test-context -f - . <<EOF
FROM busybox
COPY . /context
WORKDIR /context
CMD find .
EOF

# run the image which executes the find command
docker container run --rm test-context

# cleanup the built image
docker image rm test-context