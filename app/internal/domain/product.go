package domain

import (
	"context"
	"fmt"
	"time"

	"github.com/zYoma/yandex_kafka/internal/application/interfaces"
	"github.com/zYoma/yandex_kafka/internal/logger"
)

// Определение структуры сообщения
type Product struct {
	Id   int    `json:"id"`
	Name string `json:"name"`
}

// GenerateAndSendProducts генерирует сообщения и отправляет их через Kafka
func GenerateAndSendProducts(ctx context.Context, producer interfaces.Producer) error {
	products := GenerateProducts()

	// Преобразуем []*Product в []interface{} для отправки
	messages := make([]interface{}, len(products))
	for i, product := range products {
		messages[i] = product
	}

	return producer.SendMessages(ctx, messages)
}

// GenerateProducts генерирует массив из 10000 продуктов
func GenerateProducts() []*Product {
	products := make([]*Product, 0, 10000)

	for i := 1; i <= 10000; i++ {
		product := &Product{
			Id:   i,
			Name: fmt.Sprintf("Product %d", i),
		}
		products = append(products, product)
	}

	return products
}

// ProcessProducts обрабатывает список продуктов:  запись в HDFS
func ProcessProducts(ctx context.Context, products []Product, hdfsClient interfaces.HDFSClient) bool {
	if hdfsClient != nil {
		// Конвертируем []Product в []interfaces.Product для записи в HDFS
		interfaceProducts := make([]interfaces.Product, len(products))
		for i, p := range products {
			interfaceProducts[i] = interfaces.Product{
				Id:   p.Id,
				Name: p.Name,
			}
		}

		filename := fmt.Sprintf("products_batch_%d", time.Now().Unix())
		err := hdfsClient.WriteProductBatch(ctx, interfaceProducts, filename)
		if err != nil {
			logger.Get().Sugar().Errorf("Ошибка при записи в HDFS: %v", err)
			return false
		}
		logger.Get().Sugar().Infof("Обработано %d продуктов, записано в HDFS", len(products))
	}

	return true
}

// ConvertDomainProductToInterfaceProduct конвертирует domain.Product в interfaces.Product
func ConvertDomainProductToInterfaceProduct(products []Product) []interfaces.Product {
	result := make([]interfaces.Product, len(products))
	for i, p := range products {
		result[i] = interfaces.Product{
			Id:   p.Id,
			Name: p.Name,
		}
	}
	return result
}
