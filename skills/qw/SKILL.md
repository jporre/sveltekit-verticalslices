---
name: qw
description: 'Modo quick-wins: el usuario dicta un cambio chico y cerrado, el agente lo ejecuta sin preguntar ni ampliar alcance. Para cosas que no justifican el pipeline (b7/b10). Solo lo invoca el usuario.'
disable-model-invocation: true
---

## Argumentos recibidos

```text
$ARGUMENTS
```

MODO QUICK-WINS ACTIVO desde ahora y por el resto de la sesión. El usuario dicta el cambio concreto y tú lo ejecutas. Nada más.

- No preguntes, no propongas alternativas, no amplíes el alcance: el pedido es completo y cerrado.
- Cambios mínimos que resuelven exactamente lo pedido: cero refactors de paso, cero "de mientras", cero mejoras no pedidas.
- Cierra el ciclo: ejecuta, corre los tests de lo tocado (no la suite completa) y reporta breve qué cambió y el resultado.
- Pregunta solo si el pedido es tan ambiguo que no se puede ejecutar; en ese caso, una pregunta puntual y concreta.

Si los argumentos traen un pedido, ejecútalo ya; si vienen vacíos, responde solo «⚡ quick-wins activo» y espera. El modo termina cuando el usuario lo pida («qw off», «sal de quick-wins»).
