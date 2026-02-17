package config

import (
	"errors"

	env "github.com/caarlos0/env/v11"
	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
)

// Config представляет конфигурацию
type Config struct {
	BootstrapServers         string `env:"BOOTSTRAP_SERVER" envDefault:"kafka-0:9092,kafka-1:9092,kafka-2:9092"`
	Topic                    string `env:"TOPIC" envDefault:"test_topic"`
	Acks                     string `env:"ACKS" envDefault:"all"`
	CompressionType          string `env:"COMPRASSION_TYPE" envDefault:"zstd"`
	GroupId                  string `env:"GROUP_ID" envDefault:"test-group"`
	AutoOffsetReset          string `env:"AUTO_OFFSET_RESET" envDefault:"earliest"`
	EnableAutoCommit         bool   `env:"ENABLE_AUTO_COMMIT" envDefault:"false"`
	LingerMS                 int    `env:"LINGER_MS" envDefault:"5"`
	BatchNumMessage          int    `env:"BATCH_NUM_MESSAGE" envDefault:"10000"`
	DeliveryTimeoutMS        int    `env:"DELIVERY_TIMEOUT_MS" envDefault:"120000"`
	FetchWaitMaxMS           int    `env:"FETCH_WAIT_MAX_MS" envDefault:"100"`
	FetchMinByres            int    `env:"FETCH_MIN_BYRES" envDefault:"1"`
	Retries                  int    `env:"RETRIES" envDefault:"100"`
	MaxPollIntervalMS        int    `env:"MAX_POLL_INTERVAL_MS" envDefault:"300000"`
	SchemaRegistryServiceURL string `env:"SCHEMA_REGISTRY_SERVICE_URL" envDefault:"http://schema-registry:8081"`
	SingleMessageConsumer    bool   `env:"ENABLE_SINGLE_MESSAGE_CONSUMER" envDefault:"true"`

	UseSSL        bool   `env:"USE_SSL" envDefault:"true"`
	SASLUsername  string `env:"SASL_USERNAME" envDefault:"admin"`
	SASLPassword  string `env:"SASL_PASSWORD" envDefault:""`
	SSLCALocation string `env:"SSL_CA_LOCATION" envDefault:"/certs/ca.crt"`

	HadoopHDFSMode     bool   `env:"HADOOP_HDFS_MODE" envDefault:"false"`
	HDFSHDFSAddresses  string `env:"HDFS_ADDRESSES" envDefault:"namenode:9000"`
	HDFSKafkaDataPath  string `env:"HDFS_KAFKA_DATA_PATH" envDefault:"/kafka_data"`
	DataprocMasterHost string `env:"DATAPROC_MASTER_HOST" envDefault:""`
}

// GetConfig возвращает конфигурацию приложения из переменных окружения.
func GetConfig() (*Config, error) {
	cfg := &Config{}
	if err := env.Parse(cfg); err != nil {
		return nil, errors.New("Config: failed to parse config")
	}
	return cfg, nil
}

// GetProducerConfig возвращает конфигурацию для продюсера Kafka
func (c *Config) GetProducerConfig() *kafka.ConfigMap {
	cfgMap := &kafka.ConfigMap{
		"bootstrap.servers":   c.BootstrapServers,
		"compression.type":    c.CompressionType,
		"acks":                c.Acks,
		"linger.ms":           c.LingerMS,
		"batch.num.messages":  c.BatchNumMessage,
		"delivery.timeout.ms": c.DeliveryTimeoutMS,
		"retries":             c.Retries,
	}

	if c.UseSSL {
		cfgMap.SetKey("security.protocol", "SASL_SSL")
		cfgMap.SetKey("sasl.mechanism", "SCRAM-SHA-512")
		cfgMap.SetKey("sasl.username", c.SASLUsername)
		cfgMap.SetKey("sasl.password", c.SASLPassword)
		cfgMap.SetKey("ssl.ca.location", c.SSLCALocation)
	}

	return cfgMap
}

// GetConsumerConfig возвращает конфигурацию для консьюмера Kafka
func (c *Config) GetConsumerConfig() *kafka.ConfigMap {
	enableAutoCommit := false
	if c.SingleMessageConsumer == true {
		enableAutoCommit = true
	}

	cfgMap := &kafka.ConfigMap{
		"bootstrap.servers":    c.BootstrapServers,
		"group.id":             c.GroupId,
		"auto.offset.reset":    c.AutoOffsetReset,
		"enable.auto.commit":   enableAutoCommit,
		"fetch.wait.max.ms":    c.FetchWaitMaxMS,
		"fetch.min.bytes":      c.FetchMinByres,
		"max.poll.interval.ms": c.MaxPollIntervalMS,
	}

	if c.UseSSL {
		cfgMap.SetKey("security.protocol", "SASL_SSL")
		cfgMap.SetKey("sasl.mechanism", "SCRAM-SHA-512")
		cfgMap.SetKey("sasl.username", c.SASLUsername)
		cfgMap.SetKey("sasl.password", c.SASLPassword)
		cfgMap.SetKey("ssl.ca.location", c.SSLCALocation)
	}

	return cfgMap
}
