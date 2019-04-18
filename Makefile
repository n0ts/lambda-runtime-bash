.DEFAULT_GOAL := help

AWS_ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account)

.PHONY: build
build: # Buuild lambda function for build layer
	@zip function.zip ./bootstrap ./function.sh
	@aws lambda create-function \
	      --function-name custom-runtime-layer-creater \
	      --zip-file fileb://function.zip \
	      --handler function.handler \
	      --runtime provided \
	      --timeout 900 \
	      --memory-size 256 \
	      --environment Variables={S3_BUCKET=$(S3_BUCKET)} \
	      --role arn:aws:iam::$(AWS_ACCOUNT_ID):role/$(LAMBDA_ROLE)
	@aws lambda invoke \
	      --invocation-type Event \
	      --function-name custom-runtime-layer-creater \
	      .output.txt
	@echo "Please wait for creating s3://$(s3_BUCET)/provided.tgz"
	@rm -f function.zip

.PHONY: extract_layer
extract_layer: # Extract layer
	@test -d ./aws-cli-layer/ && rm -fr ./aws-cli-layer/
	@aws s3 cp s3://$(S3_BUCKET)/provided.tgz ./aws-cli-layer/
	@cd ./aws-cli-layer/ \
	    && mkdir ./bin \
	    && tar -xzvf ./provided.tgz -C ./bin/ \
	    && mv ./bin/bin/* ./bin/ \
	    && chmod 755 ./bin/* \
	    && rm ./provided.tgz \
	    && cd ../

.PHONY: build_layer
build_layer: # Build lambda layer
	@$(MAKE) extract_layer
	@cp ./sample/bootstrap ./aws-cli-layer/bootstrap
	@cd ./aws-cli-layer && zip -r ../aws-cli-layer.zip .
	@aws lambda publish-layer-version \
	      --layer-name aws-cli-layer \
	      --zip-file fileb://aws-cli-layer.zip
	@rm -fr ./aws-cli-layer/

.PHONY: build_sample_cli
build_sample: # Build sample function with aws-cli layer using aws-cli
	@zip function.zip -j ./sample/bootstrap ./sample/function.sh
	@layer=$(shell aws --output text lambda list-layers \
	      --query "Layers[?LayerName=='aws-cli-layer'].LatestMatchingVersion.LayerVersionArn" ) && \
	aws lambda create-function \
	      --function-name sample-with-aws-cli-layer \
	      --zip-file fileb://function.zip \
	      --handler function.handler \
	      --runtime provided \
	      --timeout 60 \
	      --role arn:aws:iam::$(AWS_ACCOUNT_ID):role/$(LAMBDA_ROLE) \
	      --layers "$$layer"
	@echo "Let's invoke lambda function sample-with-aws-cli-layer"

.PHONY: build_sam
build_sam: # Build layer and sample function with using aws-sam-cli
	@$(MAKE) extract_layer
	@sam package --template-file sam-template-with-layer.yaml \
	             --s3-bucket $(S3_BUCKET) \
	             --output-template-file .out-sam-template-with-layer.yaml

.PHONY: deploy_sam
deploy_sam: # Deploy layer and sample function with using aws-sam-cli
	@sam deploy --template-file .out-sam-template-with-layer.yaml \
	            --stack-name $(STACK_NAME)
	@echo "Let's invoke laabda function sample-included-aws-cli"

.PHONY: clean_cli
clean: # Clean cli
	@aws lambda delete-function --function-name custom-runtime-layer-creater
	@aws lambda delete-function --function-name sample-with-aws-cli-layer

.PHONY: clean_sam
clean_sam: # Clean sam
	@aws lambda delete-function --function-name sample-included-aws-cli

.PHONY: clean_all
clean_all: # Clean all
	@aws s3 rm s3://$(S3_BUCKET)/provided.tgz
	@rm -fr .out* *.zip
	@layer=$(shell aws --output text lambda list-layers \
	      --query "Layers[?LayerName=='aws-cli-layer'].LatestMatchingVersion.Version" ) && \
	      aws lambda delete-layer-version \
	         --layer-name aws-cli-layer --version-number "$$layer"

.PHONY: install
install: # Install packages
	@pip install awscli aws-sam-cli

.PHONY: help
help: # Show usage
	@echo 'Available targets are:'
	@grep -E '^[a-zA-Z_-]+:.*?# .*$$' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?# "}; {printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'
