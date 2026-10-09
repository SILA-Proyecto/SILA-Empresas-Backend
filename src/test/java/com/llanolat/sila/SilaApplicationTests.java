package com.llanolat.sila;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest(properties = {
		"sila.seguridad.jwt-secret=dGVzdC1zZWNyZXRvLWRlLXBydWViYS1zb2xvLXBhcmEtdGVzdHM=",
		"sila.seguridad.mfa-key=dGVzdC1tZmEta2V5LXBhcmEtdGVzdHMtMzItYnl0ZXMhIQ=="
})
class SilaApplicationTests {

	@Test
	void contextLoads() {
	}

}
