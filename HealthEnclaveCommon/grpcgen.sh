#!/bin/bash
protoc Sources/HealthEnclaveCommon/GRPC/HealthEnclave.proto \
    --proto_path=Sources/HealthEnclaveCommon/GRPC \
    --swift_opt=Visibility=Public \
    --swift_out=Sources/HealthEnclaveCommon/GRPC

protoc Sources/HealthEnclaveCommon/GRPC/HealthEnclave.proto \
    --proto_path=Sources/HealthEnclaveCommon/GRPC \
    --grpc-swift_opt=Visibility=Public \
    --grpc-swift_out=Sources/HealthEnclaveCommon/GRPC
