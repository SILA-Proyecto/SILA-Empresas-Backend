package com.llanolat.sila;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest(properties = {
		"sila.seguridad.jwt-secret=dGVzdC1zZWNyZXRvLWRlLXBydWViYS1zb2xvLXBhcmEtdGVzdHM=",
		"sila.seguridad.mfa-key=dGVzdC1tZmEta2V5LXBhcmEtdGVzdHMtMzItYnl0ZXMhIQ==",
		"sila.archivos.docs-key=dGVzdC1kb2NzLWtleS1wYXJhLXRlc3RzLTMyLWJ5dGVzIQ==",
		"sila.archivos.clamav.habilitado=false"
})
class SilaApplicationTests {

	@Test
	void contextLoads() {
	}

}
