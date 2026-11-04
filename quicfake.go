package hydra

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"errors"
	"io"
	"net"
	"time"
)

// Фейковый QUIC Initial с чужим именем (SNI), например vk.com. Его отправляют
// перед настоящим рукопожатием с малым TTL: оборудование провайдера (DPI)
// видит «разрешённый» сайт и пропускает поток, а до сервера пакет не доходит.
// Реализация следует RFC 9001 (защита Initial-пакетов по версии QUIC v1).

var quicV1Salt = []byte{0x38, 0x76, 0x2c, 0xf7, 0xf5, 0x59, 0x34, 0xb3, 0x4d, 0x17,
	0x9a, 0xe6, 0xa4, 0xc8, 0x0c, 0xad, 0xcc, 0xbb, 0x7f, 0x0a}

func hkdfExtract(salt, ikm []byte) []byte {
	m := hmac.New(sha256.New, salt)
	m.Write(ikm)
	return m.Sum(nil)
}

// hkdfExpandLabel — HKDF-Expand-Label из TLS 1.3 для длины до 32 байт.
func hkdfExpandLabel(secret []byte, label string, length int) []byte {
	full := "tls13 " + label
	info := []byte{byte(length >> 8), byte(length), byte(len(full))}
	info = append(info, full...)
	info = append(info, 0)
	m := hmac.New(sha256.New, secret)
	m.Write(info)
	m.Write([]byte{1})
	return m.Sum(nil)[:length]
}

func initialKeys(dcid []byte) (key, iv, hp []byte) {
	cs := hkdfExpandLabel(hkdfExtract(quicV1Salt, dcid), "client in", 32)
	return hkdfExpandLabel(cs, "quic key", 16), hkdfExpandLabel(cs, "quic iv", 12), hkdfExpandLabel(cs, "quic hp", 16)
}

func quicVarint(n int) []byte {
	switch {
	case n < 64:
		return []byte{byte(n)}
	case n < 16384:
		return []byte{0x40 | byte(n>>8), byte(n)}
	}
	return []byte{0x80 | byte(n>>24), byte(n >> 16), byte(n >> 8), byte(n)}
}

// clientHelloFor получает настоящий ClientHello TLS 1.3 с нужным SNI, дав
// стандартному TLS-клиенту «поговорить» с заглушкой.
func clientHelloFor(sni string) ([]byte, error) {
	a, b := net.Pipe()
	defer a.Close()
	defer b.Close()
	go func() {
		c := tls.Client(a, &tls.Config{
			ServerName:         sni,
			MinVersion:         tls.VersionTLS13,
			NextProtos:         []string{"h3"},
			InsecureSkipVerify: true,
		})
		c.Handshake()
	}()
	b.SetReadDeadline(time.Now().Add(2 * time.Second))
	hdr := make([]byte, 5)
	if _, err := io.ReadFull(b, hdr); err != nil {
		return nil, err
	}
	body := make([]byte, int(hdr[3])<<8|int(hdr[4]))
	if _, err := io.ReadFull(b, body); err != nil {
		return nil, err
	}
	return body, nil
}

// BuildFakeQUICInitial строит один UDP-датаграмму-«Initial» длиной size байт.
func BuildFakeQUICInitial(sni string, size int) ([]byte, error) {
	ch, err := clientHelloFor(sni)
	if err != nil {
		return nil, err
	}
	dcid := make([]byte, 8)
	scid := make([]byte, 8)
	rand.Read(dcid)
	rand.Read(scid)
	key, iv, hp := initialKeys(dcid)

	frame := append([]byte{0x06, 0x00}, quicVarint(len(ch))...) // CRYPTO, offset 0
	frame = append(frame, ch...)

	const pnLen, tagLen = 2, 16
	hdrLen := 1 + 4 + 1 + len(dcid) + 1 + len(scid) + 1 + 2 + pnLen
	payloadLen := size - hdrLen - tagLen
	if payloadLen < len(frame) {
		payloadLen = len(frame)
	}
	payload := make([]byte, payloadLen) // нули = PADDING
	copy(payload, frame)

	lengthVal := pnLen + payloadLen + tagLen
	if lengthVal >= 16384 {
		return nil, errors.New("слишком длинный Initial")
	}
	header := []byte{0xC0 | byte(pnLen-1), 0, 0, 0, 1, byte(len(dcid))}
	header = append(header, dcid...)
	header = append(header, byte(len(scid)))
	header = append(header, scid...)
	header = append(header, 0) // длина токена
	header = append(header, 0x40|byte(lengthVal>>8), byte(lengthVal))
	pnOff := len(header)
	header = append(header, 0, 0) // номер пакета 0

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	nonce := append([]byte(nil), iv...) // номер пакета 0: nonce = iv
	sealed := gcm.Seal(nil, nonce, payload, header)
	pkt := append(append([]byte(nil), header...), sealed...)

	hb, err := aes.NewCipher(hp)
	if err != nil {
		return nil, err
	}
	mask := make([]byte, 16)
	hb.Encrypt(mask, pkt[pnOff+4:pnOff+4+16])
	pkt[0] ^= mask[0] & 0x0f
	pkt[pnOff] ^= mask[1]
	pkt[pnOff+1] ^= mask[2]
	return pkt, nil
}
