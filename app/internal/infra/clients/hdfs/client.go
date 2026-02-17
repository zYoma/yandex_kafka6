package hdfs

import (
	"context"
	"encoding/csv"
	"fmt"
	"path"
	"strings"
	"time"

	"github.com/colinmarc/hdfs/v2"
	"github.com/zYoma/yandex_kafka/internal/application/interfaces"
	"github.com/zYoma/yandex_kafka/internal/logger"
)

type HDFSWriter struct {
	client    *hdfs.Client
	basePath  string
	batchSize int
}

type HDFSWriterConfig struct {
	Addresses string
	BasePath  string
	BatchSize int
}

func NewHDFSWriter(cfg *HDFSWriterConfig) (*HDFSWriter, error) {
	client, err := hdfs.NewClient(hdfs.ClientOptions{
		Addresses: strings.Split(cfg.Addresses, ","),
		User:      "hadoop",
	})
	if err != nil {
		return nil, fmt.Errorf("ошибка при создании клиента HDFS: %w", err)
	}

	err = client.MkdirAll(cfg.BasePath, 0777)
	if err != nil && !strings.Contains(err.Error(), "exists") {
		client.Close()
		return nil, fmt.Errorf("ошибка при создании директории %s: %w", cfg.BasePath, err)
	}

	batchSize := cfg.BatchSize
	if batchSize <= 0 {
		batchSize = 1000
	}

	return &HDFSWriter{
		client:    client,
		basePath:  cfg.BasePath,
		batchSize: batchSize,
	}, nil
}

func (w *HDFSWriter) WriteProductBatch(ctx context.Context, products []interfaces.Product, batchName string) error {
	if len(products) == 0 {
		logger.Get().Sugar().Warn("Пустой список продуктов для записи в HDFS")
		return nil
	}

	batchDir := path.Join(w.basePath, batchName)
	logger.Get().Sugar().Infof("Создание директории батча: %s", batchDir)
	if err := w.client.MkdirAll(batchDir, 0777); err != nil {
		return fmt.Errorf("не удалось создать директорию %s в HDFS: %w", batchDir, err)
	}

	timestamp := time.Now().Format("20060102_150405_000")
	fullFilename := path.Join(batchDir, fmt.Sprintf("kafka_data_%s.csv", timestamp))
	logger.Get().Sugar().Infof("Создание файла: %s", fullFilename)

	var csvBuilder strings.Builder
	writer := csv.NewWriter(&csvBuilder)

	for _, product := range products {
		record := []string{
			fmt.Sprintf("%d", product.Id),
			product.Name,
		}
		if err := writer.Write(record); err != nil {
			return fmt.Errorf("ошибка при записи строки в CSV: %w", err)
		}
	}
	writer.Flush()
	if err := writer.Error(); err != nil {
		return fmt.Errorf("ошибка при формировании CSV: %w", err)
	}

	csvData := csvBuilder.String()
	logger.Get().Sugar().Infof("CSV данные: %d байт", len(csvData))

	logger.Get().Sugar().Infof("Открытие файла на запись...")
	file, err := w.client.Create(fullFilename)
	if err != nil {
		return fmt.Errorf("ошибка при создании файла %s в HDFS: %w", fullFilename, err)
	}
	defer file.Close()

	logger.Get().Sugar().Infof("Запись %d байт в файл...", len(csvData))
	_, err = file.Write([]byte(csvData))
	if err != nil {
		return fmt.Errorf("ошибка при записи данных в файл %s: %w", fullFilename, err)
	}

	logger.Get().Sugar().Infof("Завершение записи...")
	if err := file.Close(); err != nil {
		return fmt.Errorf("ошибка при закрытии файла: %w", err)
	}

	logger.Get().Sugar().Infof("Успешно записано %d продуктов в HDFS: %s", len(products), fullFilename)
	return nil
}

func (w *HDFSWriter) Close() error {
	if w.client != nil {
		return w.client.Close()
	}
	return nil
}
