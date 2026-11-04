package hydra

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"testing"
)

func TestFakeQUICInitialDecrypts(t *testing.T) {
	pkt, err := BuildFakeQUICInitial("vk.com", 1357)
	if err != nil {
		t.Fatal(err)
	}
	if len(pkt) != 1357 {
		t.Fatalf("длина %d, ждали 1357 (ClientHello раздулся и фейк не влезает в один пакет)", len(pkt))
	}
	if pkt[0]&0x80 == 0 {
		t.Fatal("ждали длинный заголовок")
	}

	// разбор «как это делает сервер»
	dl := int(pkt[5])
	dcid := pkt[6 : 6+dl]
	off := 6 + dl
	off += 1 + int(pkt[off]) // SCID
	off++                    // длина токена (0)
	length := int(pkt[off]&0x3f)<<8 | int(pkt[off+1])
	off += 2
	pnOff := off

	key, iv, hp := initialKeys(dcid)
	hb, _ := aes.NewCipher(hp)
	mask := make([]byte, 16)
	hb.Encrypt(mask, pkt[pnOff+4:pnOff+4+16])
	first := pkt[0] ^ (mask[0] & 0x0f)
	pnLen := int(first&3) + 1
	hdr := append([]byte(nil), pkt[:pnOff+pnLen]...)
	hdr[0] = first
	for i := 0; i < pnLen; i++ {
		hdr[pnOff+i] ^= mask[1+i]
	}
	block, _ := aes.NewCipher(key)
	gcm, _ := cipher.NewGCM(block)
	plain, err := gcm.Open(nil, iv, pkt[pnOff+pnLen:pnOff+length], hdr)
	if err != nil {
		t.Fatalf("не расшифровывается: %v", err)
	}
	if plain[0] != 0x06 || !bytes.Contains(plain, []byte("vk.com")) {
		t.Fatalf("в CRYPTO-кадре нет ClientHello с vk.com")
	}
}
