/**
 * Mira el recorte de una prenda y dice qué es.
 *
 * ## Por qué esto existe en el servidor y no en la app
 *
 * Por una razón y solo una: **la clave**. `OPENROUTER_API_KEY` vive aquí como
 * variable de entorno de Appwrite y no sale de aquí. Un `.ipa` es un zip que
 * cualquiera puede abrir, así que una clave embarcada en la app es una clave
 * publicada — y de las que se cobran por uso.
 *
 * Todo lo que se puede resolver en el iPhone se resuelve en el iPhone. Esto
 * entra solo cuando el segmentador duda de la categoría, cuando no hay
 * subcategoría, o cuando el OCR leyó algo que parece una marca y hay que
 * confirmarlo. No es el camino normal: es el que se toma cuando el normal no
 * llega.
 *
 * ## Qué recibe
 *
 * El recorte **ya normalizado**, nunca la foto original. Sin cara, sin
 * habitación, sin el resto de la gente. Eso lo garantiza el contrato del lado
 * de Swift, que no tiene ni un campo donde meter la original.
 */

const MODEL = process.env.OPENROUTER_MODEL || 'google/gemini-2.5-flash-lite';
/**
 * El modelo que dibuja.
 *
 * Elegido **midiendo**, no leyendo la tabla de precios. El precio por token de
 * `gpt-5-image-mini` es el más bajo de la lista y resulta ser el peor de los
 * tres candidatos en las tres cosas que importan:
 *
 * | modelo | tiempo | coste real | fidelidad |
 * |---|---|---|---|
 * | gemini-3.1-flash-lite-image | 5,1 s | $0,034 | mantiene color y forma |
 * | gemini-2.5-flash-image | 7,9 s | $0,039 | mantiene color y forma |
 * | gpt-5-image-mini | 38,5 s | $0,044 | **cambió el color** |
 *
 * El precio por token engañaba: emite 4.175 tokens de imagen frente a 1.120.
 * Y la fidelidad lo descarta del todo — en la prueba pasó un salmón a naranja
 * saturado y redibujó la textura, que con ropa significa cambiarle a alguien
 * el color de una prenda que tiene en el armario.
 */
const IMAGE_MODEL = process.env.OPENROUTER_IMAGE_MODEL || 'google/gemini-3.1-flash-lite-image';
const ENDPOINT = 'https://openrouter.ai/api/v1/chat/completions';

/**
 * Lo que se le pide al modelo de imagen.
 *
 * Todo el texto empuja en la misma dirección: **es la misma prenda, puesta
 * recta**. Es lo único que separa "quítale la percha y las arrugas" de
 * "dibújame una camiseta parecida" — y lo segundo destruye el armario, porque
 * el usuario acaba con ropa que no tiene.
 */
const RESTYLE_PROMPT = `Convierte esto en la foto de producto que usaría una tienda online para ESTA prenda.

FONDO — OBLIGATORIO:
- Fondo LISO y de UN SOLO TONO GRIS CLARO (#F2F2F2), cubriendo todo lo que no sea la prenda, hasta los bordes.
- SIN degradados, SIN viñeteado, SIN sombra proyectada y SIN suelo ni superficie: solo ese gris.
- NO dibujes el patrón de cuadros grises y blancos con el que los editores representan la transparencia: eso son píxeles pintados, no un fondo vacío.
- El borde de la prenda, nítido contra el fondo.

SOLO ESTA PRENDA — OBLIGATORIO:
- En la foto puede haber más cosas: un bolso, un cinturón, otra prenda, una persona, una percha, una mano. NO FORMAN PARTE de la prenda y no deben aparecer.
- Si dudas de si algo pertenece a la prenda, DÉJALO FUERA.
- No añadas bolsillos, botones, cremalleras, cordones, estampados, etiquetas ni logotipos que no se vean con claridad en la original.

LA MISMA PRENDA — OBLIGATORIO:
- Mismo color exacto, mismo estampado, mismo logotipo y mismo texto.
- Mismo corte, mismo largo, mismo cuello, mismas mangas, mismas proporciones.

PRESENTACIÓN — PLANA SIEMPRE:
- La prenda va SOLA Y PLANA, como tendida sobre una mesa: SIN cuerpo, SIN persona, SIN maniquí, SIN percha, SIN volumen de estar puesta y SIN piernas o brazos dentro.
- Esto vale TAMBIÉN cuando la foto original es de alguien llevándola puesta: en ese caso quítala del cuerpo y dibújala tendida. Nunca devuelvas a la persona, ni su silueta, ni un maniquí invisible con la prenda hinchada.
- La vista de producto que usaría una tienda para ese tipo de prenda: camisetas, camisas, chaquetas, pantalones y vestidos de FRENTE; zapatillas y zapatos de PERFIL.
- "No la gires" se refiere solo a frente o espalda: si la original se ve por delante, la reconstrucción también. Que esté puesta no es una vista que haya que conservar.
- Prenda entera, centrada, sin recortar por ningún borde, con iluminación de estudio uniforme y sin arrugas de estar colgada.`;

/**
 * Lo que se le pide para **probarse** un outfit.
 *
 * El equilibrio es distinto al de "mejorar": allí lo sagrado es la prenda y la
 * persona sobra; aquí lo sagrado es **la persona** —su cara, su cuerpo, su
 * postura— y lo que cambia es la ropa. Si el modelo se toma libertades con la
 * cara, el resultado no es "yo con esa camiseta", es otra persona con esa
 * camiseta, y eso no sirve para decidir si te la pones.
 */
const TRYON_PROMPT = `Vísteme con estas prendas. La primera imagen soy yo; las siguientes son prendas.

LA PERSONA NO SE TOCA — OBLIGATORIO:
- Misma cara, mismo peinado, mismo tono de piel, misma complexión, misma postura y mismo encuadre.
- No la adelgaces, no la estilices, no le cambies la edad ni la expresión. Es la misma persona, vestida de otra manera.
- No añadas ni quites personas.

LA ROPA — OBLIGATORIO:
- Pon EXACTAMENTE las prendas de las imágenes: mismo color, mismo estampado, mismo corte, mismo largo, mismas mangas.
- Quita la ropa que llevara puesta en las zonas que ocupan las prendas nuevas; el resto se queda.
- Que caigan como caería la tela de verdad sobre ese cuerpo, con sus arrugas y sus sombras.
- No inventes logotipos, bolsillos, cinturones ni accesorios que no estén en las imágenes.

LA FOTO:
- Fotografía realista, con luz coherente entre la persona y el sitio donde está.
- Nada de collage, ni de recortes pegados, ni de marcas de agua.`;

/**
 * Dónde se te pone.
 *
 * El escenario es parte del encargo y no un retoque posterior: pedirle al
 * modelo que te vista y **luego** cambiarle el fondo deja la luz de un sitio
 * sobre una persona iluminada de otro, y eso se ve enseguida. Diciéndoselo de
 * una, la sombra cae donde toca.
 *
 * `plain` es el que permite recortar después: fondo liso de un solo tono, que
 * es lo que Vision sabe separar limpiamente en el teléfono.
 */
const SCENES = {
  plain: 'Fondo LISO de un solo tono gris claro (#F2F2F2), sin sombra proyectada, sin suelo y sin objetos. Solo la persona sobre ese gris.',
  studio: 'Estudio de fotografía: fondo de papel continuo claro, luz suave de softbox y una sombra corta bajo los pies.',
  street: 'Calle de ciudad de día, acera y fachadas desenfocadas al fondo, luz natural.',
  beach: 'Playa a media tarde, arena y mar desenfocados al fondo, luz cálida y baja.',
  office: 'Oficina moderna con luz de ventana, fondo desenfocado.',
  night: 'Calle de noche con luces de la ciudad desenfocadas detrás, luz fría y contraste alto.',
};

/**
 * Prueba un outfit sobre una foto de la persona.
 *
 * ## Por qué no se verifica como "mejorar"
 *
 * Porque no hay nada que verificar contra un original: el resultado es una foto
 * que no existía. Lo que sí se comprueba es que **haya** imagen y que el modelo
 * no se haya negado — y el resto lo juzga quien la mira, que para eso es su
 * cara.
 *
 * ## Lo que sale del teléfono
 *
 * Una foto de cuerpo entero de una persona y unos recortes de ropa. Es el dato
 * más sensible que maneja la app, así que la app **pide permiso expreso antes
 * de la primera vez** y aquí no se guarda nada: se manda, se recibe y se
 * devuelve. Ver `TryOnConsent` en la app.
 */
async function tryOn(person, garments, scene, key, log, error) {
  const where = SCENES[scene] || SCENES.plain;
  const content = [
    { type: 'text', text: `${TRYON_PROMPT}\n\nEL SITIO — OBLIGATORIO:\n- ${where}` },
    { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${person}` } },
  ];
  for (const garment of garments) {
    content.push({ type: 'image_url', image_url: { url: `data:image/png;base64,${garment}` } });
  }

  const response = await fetch(ENDPOINT, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${key}`,
      'HTTP-Referer': 'https://iwearit.app',
      'X-Title': 'iWearIt',
    },
    body: JSON.stringify({
      model: IMAGE_MODEL,
      modalities: ['image', 'text'],
      messages: [{ role: 'user', content }],
    }),
    // Más margen que una prenda suelta: son varias imágenes de entrada.
    signal: AbortSignal.timeout(120000),
  });

  if (response.status === 429) return { status: 429, body: { error: 'rate_limited' } };
  if (!response.ok) {
    error(`OpenRouter ${response.status}: ${(await response.text()).slice(0, 400)}`);
    return { status: 502, body: { error: 'upstream_error' } };
  }

  const completion = await response.json();
  const message = completion?.choices?.[0]?.message;
  const url = message?.images?.[0]?.image_url?.url;
  if (!url || !url.startsWith('data:image')) {
    const reason = message?.refusal || String(message?.content || '').slice(0, 200) || 'sin images[]';
    error(`probador sin imagen: ${reason}`);
    return { status: 502, body: { error: 'no_image', reason } };
  }

  const usage = completion?.usage || {};
  log(`probado con ${garments.length} prenda(s) · tokens ${usage.completion_tokens ?? '?'}`);
  return {
    status: 200,
    body: {
      imageBase64: url.slice(url.indexOf(',') + 1),
      tokens: usage.completion_tokens ?? null,
    },
  };
}

/** Pide la versión de catálogo y devuelve la imagen en base64. */
async function restyle(image, key, log, error) {
  const response = await fetch(ENDPOINT, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${key}`,
      'HTTP-Referer': 'https://iwearit.app',
      'X-Title': 'iWearIt',
    },
    body: JSON.stringify({
      model: IMAGE_MODEL,
      modalities: ['image', 'text'],
      messages: [{
        role: 'user',
        content: [
          { type: 'text', text: RESTYLE_PROMPT },
          { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${image}` } },
        ],
      }],
    }),
    signal: AbortSignal.timeout(90000),
  });

  if (response.status === 429) return { status: 429, body: { error: 'rate_limited' } };
  if (!response.ok) {
    error(`OpenRouter ${response.status}: ${(await response.text()).slice(0, 400)}`);
    return { status: 502, body: { error: 'upstream_error' } };
  }

  const completion = await response.json();
  const message = completion?.choices?.[0]?.message;
  // Los modelos de imagen la devuelven en `images`, como data URL. No en
  // `content`, que trae el texto que la acompaña y que aquí no interesa.
  const url = message?.images?.[0]?.image_url?.url;
  if (!url || !url.startsWith('data:image')) {
    // **Con el motivo dentro.** Un `no_image` a secas obliga a reproducir la
    // llamada a mano para saber si fue una negativa del modelo, un filtro de
    // contenido o un cambio en la forma de la respuesta.
    const reason = message?.refusal || String(message?.content || '').slice(0, 200) || 'sin images[]';
    error(`sin imagen: ${reason}`);
    return { status: 502, body: { error: 'no_image', reason } };
  }

  const usage = completion?.usage || {};
  const generated = url.slice(url.indexOf(',') + 1);

  // **Y se comprueba.**
  //
  // Un modelo de imagen no sabe decir que no: si le das dos zapatos a medio ver
  // te devuelve algo, y ese algo puede ser un zapato inventado. Así que la
  // revisa otro modelo —de texto, con las dos imágenes delante— y si no es la
  // misma prenda, entera y sin añadidos, no se entrega nada. El recorte de
  // siempre es peor de ver pero es verdad, y es mejor eso que una prenda que
  // el usuario no tiene.
  //
  // Cuesta unas milésimas contra los tres céntimos de la generación: negarse a
  // comprobarlo por el coste sería ahorrar en el sitio equivocado.
  const verdict = await verify(image, generated, key, log, error);
  if (!verdict.ok) {
    log(`descartada: ${verdict.reason}`);
    return { status: 422, body: { error: 'not_faithful', reason: verdict.reason } };
  }

  log(`imagen generada y verificada · tokens ${usage.completion_tokens ?? '?'}`);
  return {
    status: 200,
    body: { imageBase64: generated, tokens: usage.completion_tokens ?? null },
  };
}

/** Lo que se le exige a la reconstrucción para entregarse. */
const VERIFY_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['sameGarment', 'complete', 'noExtras', 'reason'],
  properties: {
    sameGarment: {
      type: 'boolean',
      description: 'Mismo color, corte, estampado y logotipo. El fondo y la iluminación no cuentan.',
    },
    complete: { type: 'boolean', description: 'La prenda está entera, sin recortes ni partes que falten.' },
    noExtras: { type: 'boolean', description: 'No aparece nada que no sea esa prenda, ni detalles inventados.' },
    reason: { type: 'string', description: 'Qué falla, en pocas palabras. Vacío si está bien.' },
  },
};

/**
 * ¿Es la misma prenda?
 *
 * Con las dos imágenes delante y en el mismo mensaje: preguntarlo solo sobre la
 * generada sería preguntarle si le parece bonita, no si es fiel.
 */
async function verify(original, generated, key, log, error) {
  try {
    const response = await fetch(ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${key}`,
        'HTTP-Referer': 'https://iwearit.app',
        'X-Title': 'iWearIt',
      },
      body: JSON.stringify({
        model: MODEL,
        temperature: 0,
        max_tokens: 200,
        messages: [{
          role: 'user',
          content: [
            {
              type: 'text',
              text:
                'La primera imagen es la foto original de una prenda. La segunda es una '
                + 'reconstrucción de catálogo de ESA MISMA prenda.\n\n'
                + 'IGNORA POR COMPLETO EL FONDO, LA ILUMINACIÓN, LA POSTURA Y LAS ARRUGAS: '
                + 'la reconstrucción cambia el fondo a un gris liso a propósito, quita la percha y '
                + 'alisa la prenda. Eso NO es un fallo. Juzga ÚNICAMENTE la prenda.\n\n'
                // **Y que esté plana.** Es la mitad del trabajo: si devuelve la
                // prenda puesta en alguien, el armario acaba con fotos de
                // personas en vez de con fotos de ropa, y encima se ha pagado
                // por ellas.
                + 'Responde false TAMBIÉN si la segunda imagen no está plana: si aparece una '
                + 'persona, parte de un cuerpo, un maniquí, una percha, o la prenda se ve hinchada '
                + 'como si alguien la llevara puesta. La reconstrucción tiene que ser la prenda '
                + 'sola y tendida.\n\n'
                + 'Sé exigente con la prenda. Responde false si: el color no coincide, el corte o el largo '
                + 'cambian, falta una parte de la prenda, aparece otra prenda u objeto que no '
                + 'era esa prenda, o hay detalles (bolsillos, botones, logotipos, estampados) '
                + 'que no se ven en la original.\n'
                + 'Si en la original hay dos objetos parecidos a medio ver y no se distingue '
                + 'bien cuál es la prenda, responde false.',
            },
            { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${original}` } },
            { type: 'image_url', image_url: { url: `data:image/png;base64,${generated}` } },
          ],
        }],
        response_format: {
          type: 'json_schema',
          json_schema: { name: 'verdict', strict: true, schema: VERIFY_SCHEMA },
        },
      }),
      signal: AbortSignal.timeout(30000),
    });

    if (!response.ok) {
      // Si la comprobación no se puede hacer, **se entrega igual**: fallar
      // aquí es un problema del verificador, no de la imagen, y castigar a la
      // imagen por ello sería tirar tres céntimos ya gastados.
      error(`verificación no disponible: ${response.status}`);
      return { ok: true, reason: 'sin verificar' };
    }

    const body = await response.json();
    const verdict = JSON.parse(body?.choices?.[0]?.message?.content ?? '{}');
    const ok = verdict.sameGarment && verdict.complete && verdict.noExtras;
    return { ok, reason: verdict.reason || 'no es fiel a la original' };
  } catch (cause) {
    error(`verificación falló: ${cause}`);
    return { ok: true, reason: 'sin verificar' };
  }
}

/**
 * Lo que se le pide.
 *
 * Las reglas duras van arriba del todo y repetidas en el esquema porque son lo
 * único que impide que conteste bonito en vez de contestar verdad: no inventar
 * la marca, no describir a la persona, y `null` antes que adivinar.
 */
const SYSTEM = `Identificas prendas de ropa a partir de una imagen recortada sobre fondo blanco.

REGLAS:
1. La MARCA solo se responde si está escrita de forma legible en la prenda o si
   el logotipo es inequívoco y lo describes en reasoningSignals. Si no, brand es
   null. null es la respuesta correcta y esperada para una prenda lisa.
   NUNCA deduzcas la marca por el estilo, la calidad aparente o el precio.
2. Nunca describas personas: ni cuerpo, ni piel, ni edad, ni género.
3. reasoningSignals son SOLO detalles visuales comprobables mirando la misma
   imagen ("cuello con tres botones", "suela blanca de goma", "logotipo bordado
   en el pecho izquierdo"). No expliques tu razonamiento.
4. Si dudas de un campo, ponlo a null. Una ficha con huecos es mejor que una
   ficha con inventos.
5. El COLOR lo decides tú mirando la prenda, no el color medido que te pasan: el
   dato medido confunde el azul marino con el negro y el verde oliva con el gris.
   Da el matiz real ("azul marino", no "azul"; "verde oliva", no "verde").
6. La SUBCATEGORÍA en plural cuando la prenda lo es por naturaleza —"zapatillas",
   "vaqueros", "gafas"— y en singular cuando no —"camiseta", "chaqueta"—, porque
   con ella se construye el nombre que se le enseña al usuario.

kind debe ser uno de: upperBody, outerLayer, lowerBody, wholeBody, feet, head, bag, other.`;

/**
 * El esquema, forzado por el servidor.
 *
 * Pedirlo "en JSON" y confiar es cómo se acaba parseando markdown con
 * expresiones regulares en producción.
 */
const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: [
    'kind', 'subcategory', 'colorName', 'material', 'pattern',
    'brand', 'brandConfidence', 'confidence', 'reasoningSignals',
  ],
  properties: {
    kind: {
      type: ['string', 'null'],
      enum: ['upperBody', 'outerLayer', 'lowerBody', 'wholeBody', 'feet', 'head', 'bag', 'other', null],
    },
    subcategory: {
      type: ['string', 'null'],
      description: 'En español y en minúsculas: "camisa", "vaqueros", "zapatilla".',
    },
    colorName: {
      type: ['string', 'null'],
      description:
        'El color de la prenda en español y en minúsculas, con el matiz: '
        + '"azul marino", "verde oliva", "gris marengo", "crudo". No "azul" a secas '
        + 'si es marino, ni "negro" si es azul muy oscuro.',
    },
    material: { type: ['string', 'null'] },
    pattern: { type: ['string', 'null'] },
    brand: {
      type: ['string', 'null'],
      description: 'null salvo que se lea escrita o el logotipo sea inequívoco.',
    },
    brandConfidence: { type: ['number', 'null'], minimum: 0, maximum: 1 },
    confidence: { type: ['number', 'null'], minimum: 0, maximum: 1 },
    reasoningSignals: { type: 'array', items: { type: 'string' }, maxItems: 5 },
  },
};

export default async ({ req, res, log, error }) => {
  const key = process.env.OPENROUTER_API_KEY;
  if (!key) {
    error('Falta OPENROUTER_API_KEY en el entorno de la función');
    return res.json({ error: 'not_configured' }, 500);
  }

  let body;
  try {
    body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
  } catch {
    return res.json({ error: 'bad_request' }, 400);
  }

  // **El probador va primero**: es el único que no manda `imageBase64`, sino
  // una persona y varias prendas.
  if (body?.action === 'tryon') {
    const person = body?.personBase64;
    const garments = Array.isArray(body?.garmentsBase64) ? body.garmentsBase64 : [];
    if (!person || typeof person !== 'string') {
      return res.json({ error: 'missing_person' }, 400);
    }
    if (!garments.length || garments.length > 6) {
      return res.json({ error: 'bad_garments' }, 400);
    }
    // La foto de la persona llega a 1024 de lado en JPEG: unos cientos de kB.
    // Cuatro megabytes de entrada significan que alguien manda otra cosa.
    const total = person.length + garments.reduce((sum, item) => sum + (item?.length || 0), 0);
    if (total > 6000000) {
      return res.json({ error: 'image_too_large' }, 413);
    }
    const result = await tryOn(person, garments, body?.scene, key, log, error);
    return res.json(result.body, result.status);
  }

  const image = body?.imageBase64;
  if (!image || typeof image !== 'string') {
    return res.json({ error: 'missing_image' }, 400);
  }
  // Tope de tamaño: el contrato manda un recorte de 512 en JPEG, que son unas
  // decenas de kilobytes. Un megabyte aquí significa que alguien está mandando
  // otra cosa, y conviene que falle en el borde y no en la factura.
  if (image.length > 1400000) {
    return res.json({ error: 'image_too_large' }, 413);
  }

  // Dos trabajos en un endpoint: describir la prenda y dibujarla de catálogo.
  // Comparten el mismo control de acceso, la misma clave y el mismo despliegue;
  // separarlos en dos funciones sería mantener dos de cada.
  if (body.action === 'restyle') {
    const result = await restyle(image, key, log, error);
    return res.json(result.body, result.status);
  }

  const hints = [];
  if (body.kind) hints.push(`El segmentador dice que es de tipo "${body.kind}".`);
  if (body.subcategory) hints.push(`Subcategoría estimada: "${body.subcategory}".`);
  if (body.dominantColor) {
    hints.push(
      `El color medido por el dispositivo es "${body.dominantColor}", pero se mide `
      + 'por promedio y falla con los tonos oscuros. Corrígelo si no es exacto.',
    );
  }
  if (Array.isArray(body.brandCandidates) && body.brandCandidates.length) {
    hints.push(
      `El OCR ha leído algo que podría ser: ${body.brandCandidates.join(', ')}. `
      + 'Confírmalo SOLO si lo ves escrito en la imagen; si no, brand es null.',
    );
  } else {
    hints.push('El OCR no ha leído ninguna marca. Lo más probable es que brand sea null.');
  }

  const payload = {
    model: MODEL,
    temperature: 0,
    max_tokens: 400,
    messages: [
      { role: 'system', content: SYSTEM },
      {
        role: 'user',
        content: [
          { type: 'text', text: hints.join('\n') },
          { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${image}` } },
        ],
      },
    ],
    response_format: {
      type: 'json_schema',
      json_schema: { name: 'garment', strict: true, schema: SCHEMA },
    },
  };

  const started = Date.now();
  let response;
  try {
    response = await fetch(ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${key}`,
        'HTTP-Referer': 'https://iwearit.app',
        'X-Title': 'iWearIt',
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(25000),
    });
  } catch (cause) {
    error(`OpenRouter no respondió: ${cause}`);
    return res.json({ error: 'upstream_unreachable' }, 502);
  }

  if (response.status === 429) return res.json({ error: 'rate_limited' }, 429);
  if (!response.ok) {
    error(`OpenRouter ${response.status}: ${(await response.text()).slice(0, 400)}`);
    return res.json({ error: 'upstream_error' }, 502);
  }

  const completion = await response.json();
  const content = completion?.choices?.[0]?.message?.content;
  if (!content) return res.json({ error: 'empty_answer' }, 502);

  let answer;
  try {
    answer = JSON.parse(content);
  } catch {
    error(`Respuesta no parseable: ${String(content).slice(0, 400)}`);
    return res.json({ error: 'unparseable' }, 502);
  }

  // **Última barrera contra la marca inventada.**
  //
  // El esquema obliga al formato, no a la honestidad: el modelo puede rellenar
  // `brand` con algo plausible y una confianza alta. Si el OCR no leyó nada y
  // el modelo no describe ninguna señal visible que lo sostenga, la marca se
  // cae aquí y no llega al iPhone.
  const sawSomething = Array.isArray(answer.reasoningSignals)
    && answer.reasoningSignals.some((signal) => /logo|logotipo|marca|escrit|bordad|etiquet|texto/i.test(signal));
  const ocrSuggested = Array.isArray(body.brandCandidates) && body.brandCandidates.length > 0;
  if (answer.brand && !sawSomething && !ocrSuggested) {
    log(`Marca descartada por falta de evidencia visible: ${answer.brand}`);
    answer.brand = null;
    answer.brandConfidence = null;
  }

  log(`resuelto en ${Date.now() - started} ms · ${answer.kind ?? '?'} / ${answer.subcategory ?? '?'}`);
  return res.json(answer);
};
