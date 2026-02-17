package application

import (
	"context"
	"errors"

	"github.com/zYoma/yandex_kafka/internal/application/config"
	"github.com/zYoma/yandex_kafka/internal/application/interfaces"
	"github.com/zYoma/yandex_kafka/internal/domain"
	"github.com/zYoma/yandex_kafka/internal/logger"
)

// ErrAppStopped возникает при остановке приложения.
var ErrAppStopped = errors.New("app stoped")

// ProducerApp представляет приложение продюсер.
type ProducerApp struct {
	Producer interfaces.Producer
	Config   *config.Config
}

// ConsumerApp представляет приложение консьюмер.
type ConsumerApp struct {
	Consumer   interfaces.Consumer
	Config     *config.Config
	HDFSClient interfaces.HDFSClient
}

// NewProducer создаёт новое приложение продюсер с настройками из конфигурации.
func NewProducer(cfg *config.Config, producer interfaces.Producer) *ProducerApp {
	return &ProducerApp{
		Producer: producer,
		Config:   cfg,
	}
}

// NewConsumer создаёт новое приложение консьюмер с настройками из конфигурации.
func NewConsumer(cfg *config.Config, consumer interfaces.Consumer) *ConsumerApp {
	return &ConsumerApp{
		Consumer: consumer,
		Config:   cfg,
	}
}

// NewConsumerWithHDFS создаёт новое приложение консьюмер с HDFS клиентом.
func NewConsumerWithHDFS(cfg *config.Config, consumer interfaces.Consumer, hdfsClient interfaces.HDFSClient) *ConsumerApp {
	return &ConsumerApp{
		Consumer:   consumer,
		Config:     cfg,
		HDFSClient: hdfsClient,
	}
}

func (p *ProducerApp) Run(ctx context.Context) error {
	logger.Get().Info("run producer")
	err := domain.GenerateAndSendProducts(ctx, p.Producer)
	if err != nil {
		return err
	}
	return nil
}

func (c *ConsumerApp) Run(ctx context.Context) error {
	logger.Get().Sugar().Infof("run consumer, group_id: %v, topic: %v, hdfs_enabled=%v", c.Config.GroupId, c.Config.Topic, c.HDFSClient != nil)
	if c.Config.SingleMessageConsumer == true {
		return c.Consumer.StartSingleMessage(ctx)
	}
	return c.Consumer.StartBatchMessage(ctx)
}
