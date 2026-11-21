package hydra

import (
	"bufio"
	"context"
	"crypto/tls"
	"crypto/x509"
	_ "embed"
	"errors"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Корневые сертификаты, встроенные в приложение (набор Mozilla). На старых прошивках (приставки Android TV на
// Android 9) системное хранилище устарело и не знает новых корней, из-за чего регистрация WARP падает с
// «certificate signed by unknown authority». Встроенные корни только ДОБАВЛЯЮТСЯ к системным.
//
//go:embed roots.pem
var embeddedRoots []byte

var (
	rootsOnce sync.Once
	rootsPool *x509.CertPool
	clockSkew atomic.Int64 // разница «время сервера минус время устройства», нс
	skewDone  atomic.Bool
)

func rootPool() *x509.CertPool {
	rootsOnce.Do(func() {
		p, err := x509.SystemCertPool()
		if err != nil || p == nil {
			p = x509.NewCertPool()
		}
		p.AppendCertsFromPEM(embeddedRoots)
		rootsPool = p
	})
	return rootsPool
}

// tlsNow — время для проверки сертификатов с поправкой на неверные часы устройства.
func tlsNow() time.Time { return time.Now().Add(time.Duration(clockSkew.Load())) }

func isCertTimeError(err error) bool {
	var ci x509.CertificateInvalidError
	if errors.As(err, &ci) {
		return ci.Reason == x509.Expired
	}
	return strings.Contains(err.Error(), "expired or is not yet valid")
}

// learnClockSkew узнаёт время по заголовку Date ответа 1.1.1.1. Проверка сертификата на этом соединении отключена
// намеренно: нужен лишь заголовок Date, никакие секреты по нему не передаются. Поправка включается, только если часы
// устройства врут больше чем на 10 минут. Работает один раз за запуск; true — поправка найдена и сохранена.
func learnClockSkew(ctx context.Context, dial func(ctx context.Context, network, addr string) (net.Conn, error)) bool {
	if !skewDone.CompareAndSwap(false, true) {
		return false
	}
	cctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	raw, err := dial(cctx, "tcp", "1.1.1.1:443")
	if err != nil {
		return false
	}
	defer raw.Close()
	_ = raw.SetDeadline(time.Now().Add(8 * time.Second))
	tc := tls.Client(raw, &tls.Config{ServerName: "one.one.one.one", InsecureSkipVerify: true, MinVersion: tls.VersionTLS12})
	if err := tc.HandshakeContext(cctx); err != nil {
		return false
	}
	if _, err := tc.Write([]byte("HEAD / HTTP/1.1\r\nHost: one.one.one.one\r\nConnection: close\r\n\r\n")); err != nil {
		return false
	}
	resp, err := http.ReadResponse(bufio.NewReader(tc), nil)
	if err != nil {
		return false
	}
	resp.Body.Close()
	t, err := http.ParseTime(resp.Header.Get("Date"))
	if err != nil {
		return false
	}
	skew := time.Until(t)
	if skew < 10*time.Minute && skew > -10*time.Minute {
		return false
	}
	clockSkew.Store(int64(skew))
	Logf("⏰ часы устройства неверны на %s: для проверки сертификатов использую время сервера", skew.Round(time.Minute))
	return true
}
