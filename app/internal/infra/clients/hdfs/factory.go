package hdfs

import (
	"context"

	"github.com/zYoma/yandex_kafka/internal/application/config"
	"github.com/zYoma/yandex_kafka/internal/application/interfaces"
)

func NewHDFSClient(cfg *config.Config) (interfaces.HDFSClient, error) {
	hdfsCfg := &HDFSWriterConfig{
		Addresses: cfg.HDFSHDFSAddresses,
		BasePath:  cfg.HDFSKafkaDataPath,
		BatchSize: 1000,
	}

	if hdfsCfg.Addresses == "" {
		// Если HDFS не настроен, возвращаем mock-клиент
		return &MockHDFSWriter{}, nil
	}

	return NewHDFSWriter(hdfsCfg)
}

type MockHDFSWriter struct{}

func (m *MockHDFSWriter) WriteProductBatch(_ context.Context, _ []interfaces.Product, _ string) error {
	return nil
}

func (m *MockHDFSWriter) Close() error {
	return nil
}
