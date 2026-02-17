package main

import (
	"context"
	"errors"
	"os/signal"
	"syscall"

	"github.com/zYoma/yandex_kafka/internal/application"
	"github.com/zYoma/yandex_kafka/internal/application/config"
	"github.com/zYoma/yandex_kafka/internal/infra/clients/hdfs"
	"github.com/zYoma/yandex_kafka/internal/infra/clients/kafka"
	"github.com/zYoma/yandex_kafka/internal/logger"
)

func main() {
	config, err := config.GetConfig()
	if err != nil {
		panic(err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	_, deserializer, err := kafka.SchemaMigration(config)
	if err != nil {
		panic(err)
	}

	consumerClient, err := kafka.NewKafkaConsumer(deserializer, config)
	if err != nil {
		panic(err)
	}

	hdfsClient, err := hdfs.NewHDFSClient(config)
	if err != nil {
		logger.Get().Sugar().Warnf("Не удалось создать HDFS клиент: %v. Продолжаем без HDFS.", err)
		hdfsClient = nil
	}

	consumerClient.SetHDFSClient(hdfsClient)

	consumer := application.NewConsumerWithHDFS(config, consumerClient, hdfsClient)

	if err := consumer.Run(ctx); err != nil {
		if errors.Is(err, application.ErrAppStopped) {
			logger.Get().Info("consumer stopped")
			return
		}
		panic(err)
	}
}
