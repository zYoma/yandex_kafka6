package interfaces

import (
	"context"
)

// Producer предоставляет интерфейс продюсера.
type Producer interface {
	// SendMessages отправляет сообщения в топик
	SendMessages(ctx context.Context, messages []interface{}) error
}

// Consumer предоставляет интерфейс консьюмера.
type Consumer interface {
	// консьюмер запускается в режиме поочередной обработки сообщений
	StartBatchMessage(ctx context.Context) error
}

// Product представляет продукт для записи в HDFS
type Product struct {
	Id   int    `json:"id"`
	Name string `json:"name"`
}

// HDFSClient предоставляет интерфейс для работы с Hadoop HDFS.
type HDFSClient interface {
	// WriteProductBatch записывает список продуктов в файл в HDFS
	WriteProductBatch(ctx context.Context, products []Product, filename string) error
	// Close закрывает соединение с HDFS
	Close() error
}
