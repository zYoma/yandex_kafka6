package hdfs

import (
	"bytes"
	"context"
	"encoding/csv"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path"
	"strings"
	"time"

	"github.com/zYoma/yandex_kafka/internal/application/interfaces"
	"github.com/zYoma/yandex_kafka/internal/logger"
)

type WebHDFSWriter struct {
	baseURL   string
	user      string
	basePath  string
	batchSize int
}

func NewWebHDFSWriter(cfg *HDFSWriterConfig) (*WebHDFSWriter, error) {
	baseURL := strings.Split(cfg.Addresses, ",")[0]
	if !strings.HasPrefix(baseURL, "http") {
		baseURL = "http://" + baseURL + ":9870"
	}

	batchSize := cfg.BatchSize
	if batchSize <= 0 {
		batchSize = 1000
	}

	return &WebHDFSWriter{
		baseURL:   baseURL,
		user:      "hadoop",
		basePath:  cfg.BasePath,
		batchSize: batchSize,
	}, nil
}

func (w *WebHDFSWriter) buildURL(hdfsPath string, params map[string]string) string {
	u, _ := url.Parse(w.baseURL + "/webhdfs/v1" + hdfsPath)
	q := u.Query()
	q.Set("user.name", w.user)
	for k, v := range params {
		q.Set(k, v)
	}
	u.RawQuery = q.Encode()
	return u.String()
}

func (w *WebHDFSWriter) mkdir(hdfsPath string) error {
	params := map[string]string{
		"op":         "MKDIRS",
		"permission": "0777",
	}
	fullURL := w.buildURL(hdfsPath, params)

	req, err := http.NewRequest("PUT", fullURL, nil)
	if err != nil {
		return fmt.Errorf("ошибка при создании запроса: %w", err)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("ошибка при создании директории: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("ошибка при создании директории: %s", string(body))
	}

	return nil
}

func (w *WebHDFSWriter) write(hdfsPath string, content string) (*http.Response, error) {
	params := map[string]string{
		"op":        "CREATE",
		"overwrite": "true",
	}

	redirectURL := w.buildURL(hdfsPath, params)

	req, err := http.NewRequest("PUT", redirectURL, nil)
	if err != nil {
		return nil, fmt.Errorf("ошибка при создании запроса: %w", err)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("ошибка при создании файла: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusTemporaryRedirect && resp.StatusCode != http.StatusSeeOther {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("ожидался redirect, получен статус %d: %s", resp.StatusCode, string(body))
	}

	location := resp.Header.Get("Location")
	if location == "" {
		return nil, fmt.Errorf("нет Location header в redirect")
	}

	req2, err := http.NewRequest("PUT", location, bytes.NewBufferString(content))
	if err != nil {
		return nil, fmt.Errorf("ошибка при создании запроса записи: %w", err)
	}
	req2.Header.Set("Content-Type", "application/octet-stream")

	return http.DefaultClient.Do(req2)
}

func (w *WebHDFSWriter) WriteProductBatch(ctx context.Context, products []interfaces.Product, batchName string) error {
	if len(products) == 0 {
		logger.Get().Sugar().Warn("Пустой список продуктов для записи в HDFS")
		return nil
	}

	batchDir := path.Join(w.basePath, batchName)
	logger.Get().Sugar().Infof("WebHDFS: Создание директории %s", batchDir)
	if err := w.mkdir(batchDir); err != nil {
		return fmt.Errorf("не удалось создать директорию %s: %w", batchDir, err)
	}

	timestamp := time.Now().Format("20060102_150405_000")
	fullFilename := path.Join(batchDir, fmt.Sprintf("kafka_data_%s.csv", timestamp))
	logger.Get().Sugar().Infof("WebHDFS: Создание файла %s", fullFilename)

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
	logger.Get().Sugar().Infof("WebHDFS: Запись %d байт в файл", len(csvData))

	resp, err := w.write(fullFilename, csvData)
	if err != nil {
		return fmt.Errorf("ошибка при записи в файл %s: %w", fullFilename, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("ошибка при записи данных: статус %d, ответ: %s", resp.StatusCode, string(body))
	}

	logger.Get().Sugar().Infof("Успешно записано %d продуктов через WebHDFS: %s", len(products), fullFilename)
	return nil
}

func (w *WebHDFSWriter) Close() error {
	return nil
}
