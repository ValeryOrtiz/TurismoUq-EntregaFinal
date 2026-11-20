#!/usr/bin/env python3
"""Llena la plantilla del documento final de TurismoUQ.

Uso: python3 build_doc.py PLANTILLA.docx SALIDA.docx [datos.json]
Los valores que dependen de la ejecucion en Oracle se leen de datos.json; si
no estan, quedan como marcadores resaltados en amarillo [[...]].
"""
import copy, json, os, re, sys
from xml.sax.saxutils import escape
import docx
from docx.shared import Cm
from docx.oxml import parse_xml
from docx.table import Table
from docx.text.paragraph import Paragraph

TPL, OUT = sys.argv[1], sys.argv[2]
DATA = json.load(open(sys.argv[3])) if len(sys.argv) > 3 and os.path.exists(sys.argv[3]) else {}
ROOT = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(ROOT, '..', 'scripts')
IMG = os.path.join(ROOT, 'img')

W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
doc = docx.Document(TPL)
body = doc.element.body
E = list(body.iterchildren())          # elementos originales, por indice


def v(key, hint=None):
    """Valor de datos.json o marcador [[...]]."""
    if key in DATA and DATA[key] not in (None, ''):
        return str(DATA[key])
    return '[[' + (hint or key) + ']]'


# ---------------------------------------------------------------- runs / parrafos
def run_xml(text, bold=False, italic=False, size=None, font=None, color=None):
    """Un run; los [[marcadores]] salen resaltados en amarillo."""
    out = []
    for part in re.split(r'(\[\[.*?\]\])', text):
        if not part:
            continue
        rpr = ''
        if font:
            rpr += f'<w:rFonts w:ascii="{font}" w:hAnsi="{font}" w:cs="{font}"/>'
        if bold:
            rpr += '<w:b w:val="1"/><w:bCs w:val="1"/>'
        if italic:
            rpr += '<w:i w:val="1"/><w:iCs w:val="1"/>'
        if color:
            rpr += f'<w:color w:val="{color}"/>'
        if size:
            rpr += f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/>'
        if part.startswith('[['):
            rpr += '<w:highlight w:val="yellow"/>'
        out.append(f'<w:r><w:rPr>{rpr}</w:rPr><w:t xml:space="preserve">{escape(part)}</w:t></w:r>')
    return ''.join(out)


def rich(text, size=None, base_bold=False):
    """Texto con **negrita** y `codigo` en linea."""
    out = []
    for part in re.split(r'(\*\*.*?\*\*|`.*?`)', text):
        if not part:
            continue
        if part.startswith('**'):
            out.append(run_xml(part[2:-2], bold=True, size=size))
        elif part.startswith('`'):
            out.append(run_xml(part[1:-1], font='Consolas', size=(size or 22) - 2))
        else:
            out.append(run_xml(part, bold=base_bold, size=size))
    return ''.join(out)


def p_xml(runs, jc='both', before=80, after=80, line=264, keep_next=False, ind=None, shade=None, extra=''):
    ppr = '<w:pPr>'
    if keep_next:
        ppr += '<w:keepNext w:val="1"/>'
    ppr += '<w:widowControl w:val="0"/>'
    if shade:
        ppr += f'<w:shd w:val="clear" w:color="auto" w:fill="{shade}"/>'
    ppr += f'<w:spacing w:after="{after}" w:before="{before}" w:line="{line}" w:lineRule="auto"/>'
    if ind:
        ppr += ind
    ppr += f'<w:jc w:val="{jc}"/>{extra}</w:pPr>'
    return f'<w:p {W}>{ppr}{runs}</w:p>'


class Cursor:
    """Inserta elementos uno tras otro despues de un ancla."""
    def __init__(self, anchor):
        self.last = anchor

    def add(self, xml_or_el):
        el = parse_xml(xml_or_el) if isinstance(xml_or_el, str) else xml_or_el
        self.last.addnext(el)
        self.last = el
        return el

    def para(self, text, **kw):
        return self.add(p_xml(rich(text), **kw))

    def bullets(self, items):
        for it in items:
            self.add(p_xml(run_xml('•  ') + rich(it), before=20, after=20, jc='left',
                           ind='<w:ind w:left="500" w:hanging="250"/>'))

    def label(self, text):
        return self.add(p_xml(run_xml(text, bold=True), before=160, after=60, jc='left', keep_next=True))

    def code(self, text, size=15):
        lines = text.rstrip('\n').split('\n')
        for i, ln in enumerate(lines):
            self.add(p_xml(run_xml(ln if ln else ' ', font='Consolas', size=size),
                           jc='left', before=60 if i == 0 else 0,
                           after=60 if i == len(lines) - 1 else 0, line=240,
                           keep_next=i < len(lines) - 1 and len(lines) < 40, shade='F3F3F3'))

    def caption(self, text):
        return self.add(p_xml(run_xml(text, italic=True, size=18), jc='center', before=40, after=160))

    def image(self, path, width_cm):
        p = self.add(p_xml('', jc='center', before=120, after=40, keep_next=True))
        Paragraph(p, doc).add_run().add_picture(path, width=Cm(width_cm))
        return p

    def placeholder(self, text):
        return self.add(p_xml(run_xml('[[' + text + ']]', italic=True), jc='center', before=120, after=120))

    def table(self, headers, rows, widths, sizes=20, header_fill='efefef', center_cols=()):
        self.add(table_xml(headers, rows, widths, sizes, header_fill, center_cols))
        self.add(p_xml('', before=0, after=60))


def cell_xml(text, width, bold=False, fill='auto', size=20, jc='left'):
    paras = ''.join(p_xml(rich(t, size=size, base_bold=bold), jc=jc, before=0, after=0, line=240)
                    for t in str(text).split('\n'))
    return (f'<w:tc><w:tcPr><w:tcW w:w="{width}" w:type="dxa"/><w:shd w:fill="{fill}" w:val="clear"/>'
            f'<w:tcMar><w:top w:w="60" w:type="dxa"/><w:left w:w="90" w:type="dxa"/>'
            f'<w:bottom w:w="60" w:type="dxa"/><w:right w:w="90" w:type="dxa"/></w:tcMar>'
            f'<w:vAlign w:val="center"/></w:tcPr>{paras}</w:tc>')


def table_xml(headers, rows, widths, size=20, header_fill='efefef', center_cols=()):
    b = '<w:{0} w:color="000000" w:space="0" w:sz="8" w:val="single"/>'
    borders = ''.join(b.format(x) for x in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'))
    x = (f'<w:tbl {W}><w:tblPr><w:tblW w:w="{sum(widths)}" w:type="dxa"/><w:jc w:val="center"/>'
         f'<w:tblBorders>{borders}</w:tblBorders><w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid>'
         + ''.join(f'<w:gridCol w:w="{w}"/>' for w in widths) + '</w:tblGrid>')
    x += '<w:tr><w:trPr><w:cantSplit/><w:tblHeader/></w:trPr>' + ''.join(
        cell_xml(h, w, True, header_fill, size, 'center') for h, w in zip(headers, widths)) + '</w:tr>'
    for r in rows:
        x += '<w:tr><w:trPr><w:cantSplit/></w:trPr>' + ''.join(
            cell_xml(c, w, False, 'auto', size, 'center' if i in center_cols else 'left')
            for i, (c, w) in enumerate(zip(r, widths))) + '</w:tr>'
    return x + '</w:tbl>'


# ---------------------------------------------------------- tablas existentes
def tbl(i):
    return Table(E[i], doc)


def set_cell(cell, text, bold=False, size=20):
    tc = cell._tc
    ps = tc.findall('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}p')
    jc = 'left'
    if ps:
        j = ps[0].find('.//{http://schemas.openxmlformats.org/wordprocessingml/2006/main}jc')
        if j is not None:
            jc = j.get('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}val')
    for p in ps:
        tc.remove(p)
    for t in str(text).split('\n'):
        tc.append(parse_xml(p_xml(rich(t, size=size, base_bold=bold), jc=jc, before=0, after=0, line=240)))


def fill_table(t, rows, start=1):
    """Escribe filas; agrega filas copiando la ultima si faltan y quita las sobrantes."""
    need = start + len(rows)
    while len(t.rows) < need:
        t._tbl.append(copy.deepcopy(t.rows[-1]._tr))
    while len(t.rows) > need:
        t._tbl.remove(t.rows[-1]._tr)
    for i, r in enumerate(rows):
        for j, val in enumerate(r):
            if val is not None:
                set_cell(t.rows[start + i].cells[j], val)


def set_par(i, text, jc=None):
    """Reemplaza el texto de un parrafo de la plantilla (quita el azul)."""
    p = E[i]
    for r in p.findall('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}r'):
        p.remove(r)
    for el in parse_xml(f'<w:p {W}>' + rich(text) + '</w:p>').iterchildren():
        p.append(el)
    return p


def replace_par(i):
    """Quita un parrafo de instrucciones y devuelve un cursor en su lugar."""
    p = E[i]
    prev = p.getprevious()
    p.getparent().remove(p)
    return Cursor(prev)


def read(name):
    return open(os.path.join(SCRIPTS, name), encoding='utf-8').read()


def between(text, start, end, include_end=True, after=None):
    a = text.index(start, text.index(after) if after else 0)
    b = text.index(end, a)
    return text[a:b + (len(end) if include_end else 0)]


PKG = read('04_paquete.sql')
QRY = read('03_consultas_analisis.sql')
TRG = read('05_disparadores.sql')
MVS = read('06_vista_materializada.sql')
TXS = read('07_transacciones.sql')
USR = read('00_usuario_y_tablespaces.sql')

# ============================================================== PORTADA
set_par(5, 'TurismoUQ — ' + v('equipo', 'Nombre del equipo'))
set_par(7, 'Documento final · Versión 1.0 · Grupo 01N')
set_par(19, 'Valery Andrea Ortiz Mesa — ' + v('codigo_valery', 'código de Valery'))
set_par(20, 'Jhonatan David Vivas Arango — ' + v('codigo_david', 'código de Jhonatan David'))

fill_table(tbl(34), [
    ['26/09/30', '0.1', 'Entrega 1: MER, reglas de negocio, DDL, carga de datos y 7 consultas de análisis', 'Valery Ortiz y Jhonatan Vivas'],
    ['26/10/22', '0.2', 'Entrega 1 corregida y Entrega 2: paquete PL/SQL, disparadores, tablespace y vista materializada', 'Valery Ortiz y Jhonatan Vivas'],
    ['26/11/16', '1.0', 'Documento final: correcciones de la Entrega 2, Entrega 3 (transacciones, concurrencia, índices y seguridad), manual y video', 'Valery Ortiz y Jhonatan Vivas'],
])

p = E[36]
for r in p.findall('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}r')[2:]:
    p.remove(r)
p.append(parse_xml(f'<w:p {W}>' + run_xml(
    'Entregamos la base de datos de TurismoUQ en Oracle: el modelo y la carga de datos asimétricos, '
    'siete consultas de análisis para la gerencia, la lógica de negocio en PL/SQL (paquete, disparadores, '
    'vista materializada y tablespace del histórico) y su administración: transacciones con SAVEPOINT, '
    'control de concurrencia, índices medidos con planes de ejecución y seguridad por roles, vistas y perfil.',
    size=24) + '</w:p>')[0])

# ============================================================== 1. DATOS DEL EQUIPO
fill_table(tbl(39), [
    ['Valery Andrea Ortiz Mesa', v('codigo_valery', 'código'), v('correo_valery', 'correo'),
     'Modelo, carga de datos, consultas de análisis y seguridad (roles, vistas y perfil)'],
    ['Jhonatan David Vivas Arango', v('codigo_david', 'código'), v('correo_david', 'correo'),
     'Capa PL/SQL y disparadores, transacciones, concurrencia e índices'],
])
fill_table(tbl(41), [
    [None, '01N'],
    [None, v('equipo', 'Nombre del equipo')],
    [None, 'Oracle AI Database 26ai Free, versión 23.26.3, en contenedor Docker (imagen gvenzl/oracle-free)'],
    [None, 'FREEPDB1 (Service name, no SID), localhost:1521'],
    [None, 'TURISMOUQ (lo crea el script 00)'],
    [None, 'https://github.com/ValeryOrtiz/turismouq'],
    [None, v('fecha_prueba', 'aa/mm/dd de la última prueba')],
    [None, v('video', 'URL del video')],
])

# ============================================================== 2. ENCARGO
c = replace_par(44)
c.para('TurismoUQ es la base de datos de una plataforma que reúne la oferta de alojamiento de los 12 municipios '
       'del Quindío —fincas cafeteras, hoteles, glampings y hostales— y gestiona sus reservas, pagos, servicios '
       'complementarios y reseñas. No es una aplicación: es el modelo, la lógica que vive dentro del motor y su '
       'administración.')
c.para('La usan cuatro tipos de personas. Los **clientes** reservan una o varias habitaciones, pagan de una vez o '
       'por abonos y, si se hospedaron, dejan una reseña. Los **encargados de alojamiento** administran las '
       'habitaciones, tarifas y reservas de su propio establecimiento. Los **administradores** de la plataforma '
       'gestionan usuarios y catálogos. La **gerencia** consulta la ocupación, los ingresos y la rentabilidad.')
c.para('La estacionalidad del Quindío condiciona todo el modelo. La demanda se dispara en Semana Santa, mitad de '
       'año y diciembre-enero, y cae el resto del tiempo, así que el precio de una habitación no es fijo: depende '
       'de la temporada, cada temporada pertenece a un año (Semana Santa cambia de fecha) y una misma estadía '
       'puede atravesar dos temporadas. Por eso el precio se guarda por habitación y temporada (TARIFA), el valor '
       'de una estadía se calcula noche por noche en lugar de almacenarse, y los datos de prueba tienen picos '
       'reales en esos meses para que ROLLUP, PIVOT y RANK muestren diferencias.')

c = replace_par(46)
c.para('Una reserva puede incluir varias habitaciones del mismo alojamiento, y cada habitación puede tener fechas '
       'ligeramente distintas dentro del rango general (alguien del grupo llega un día después). La relación '
       'entre RESERVA y HABITACION es entonces de muchos a muchos con atributos propios, y se resolvió con la '
       'tabla asociativa **RESERVA_HABITACION**, que funciona como línea de reserva:')
c.bullets([
    '**RESERVA** es la cabecera: cliente, rango general (check-in y check-out), fecha de reserva, estado y fecha de cancelación.',
    '**RESERVA_HABITACION** guarda una fila por habitación tomada, con sus propias fechas y el número de huéspedes. '
    'Tiene llave surrogada `reserva_habitacion_id`, FK a RESERVA y a HABITACION, y `UNIQUE (reserva_id, habitacion_id, fecha_checkin)` para no duplicar una línea.',
    'Los pagos, servicios y la reseña cuelgan de la cabecera, porque se pagan y se califican por reserva, no por habitación.',
    'Las reglas que no caben en un CHECK se validan en PL/SQL: `sp_agregar_habitacion` exige que todas las líneas sean del mismo alojamiento y estén dentro del rango de la reserva, y el disparador compuesto `trg_reshab_no_solape` impide que una línea se cruce con otra de la misma habitación.',
])
c.para('Descartamos guardar la habitación como columna de RESERVA (obligaría a crear una reserva por habitación y '
       'a repetir pagos y servicios) y descartamos una lista de habitaciones en un solo campo (no se puede validar '
       'ni consultar con SQL). Con la línea de reserva, el control de solapes se hace línea por línea, que es '
       'exactamente donde ocurre.')

c = replace_par(48)
c.para('**TEMPORADA** guarda cada temporada con su categoría (ALTA, MEDIA o BAJA), su año y su rango de fechas; '
       '**TARIFA** guarda el precio por noche de cada habitación en cada temporada, con llave compuesta '
       '`(habitacion_id, temporada_id)`. Así un alojamiento puede subir poco su tarifa de temporada alta para '
       'competir por volumen: no hay un porcentaje fijo sobre un precio base. TARIFA es el cruce completo '
       'HABITACION × TEMPORADA y se genera con PL/SQL, no se digita.')
c.para('El valor de una estadía no se almacena: `pkg_turismo.fn_valor_estadia` lo calcula noche por noche. Recorre '
       'cada noche desde el check-in hasta la víspera del check-out (la noche del check-out no se cobra) y suma la '
       'tarifa de la temporada que contiene esa noche. Para no consultar la base en cada noche, guarda en variables '
       'la temporada vigente y solo vuelve a buscar cuando la noche se sale de ella. En el ejemplo del enunciado, '
       'una estadía del 20 al 26 de diciembre con el corte el 24 cobra cuatro noches (20 a 23) con la tarifa media '
       'y dos (24 y 25) con la alta.')
c.para('Para que cada noche caiga en una sola temporada:')
c.bullets([
    'Las temporadas de cada año cubren todos los días, sin huecos, de 2024 a 2027 (10 por año).',
    '`CHECK` de fechas (`fecha_fin >= fecha_inicio`) y de año (las dos fechas en el año declarado), y `UNIQUE (nombre, anio)`.',
    'El disparador de sentencia `trg_temporada_sin_cruce` rechaza con ORA-20014 cualquier temporada que se cruce con otra (un CHECK no puede comparar filas entre sí).',
    'Si aun así una noche no tiene temporada, la función no inventa un precio: lanza ORA-20006 indicando la noche; si una noche cae en dos temporadas, lanza ORA-20007.',
])

c = replace_par(50)
c.para('Las reglas se dedujeron del enunciado; cada una se hace cumplir dentro del motor. Las reglas RN7 y RN8 '
       'se agregaron en esta versión y RN1 pasó de estar planteada a estar implementada.')
fill_table(tbl(51), [
    ['RN1', 'Con más de 5 días de anticipación al check-in la cancelación reembolsa el 80 % de lo pagado; con 5 días o menos no hay reembolso',
     '`pkg_turismo.sp_cancelar_reserva` (fila REEMBOLSADO); columna `RESERVA.fecha_cancelacion` con CHECK; los datos de carga cumplen la regla'],
    ['RN2', 'Un cliente solo puede reseñar un alojamiento si tuvo al menos una reserva completada allí',
     'Disparador `trg_resena_valida` (BEFORE INSERT/UPDATE sobre RESENA, ORA-20013); `UNIQUE (reserva_id)` en RESENA'],
    ['RN3', 'Una habitación no puede estar en dos reservas activas con fechas que se crucen; el día de check-out queda libre',
     '`sp_crear_reserva` (ORA-20001 y bloqueo FOR UPDATE) y disparador compuesto `trg_reshab_no_solape` (ORA-20011)'],
    ['RN4', 'Todas las habitaciones de una reserva son del mismo alojamiento y sus fechas caen dentro del rango de la reserva',
     '`pkg_turismo.sp_agregar_habitacion` (ORA-20010 y ORA-20002); `CHECK (fecha_checkout > fecha_checkin)`'],
    ['RN5', 'El número de huéspedes de una habitación no supera su capacidad máxima',
     '`sp_crear_reserva` (ORA-20003); `CHECK (num_huespedes > 0)` y `CHECK (capacidad_maxima > 0)`'],
    ['RN6', 'Una reserva está pagada solo cuando lo pagado (exitosos menos reembolsos) cubre la estadía más los servicios',
     '`pkg_turismo.fn_reserva_pagada`; `sp_reservar_y_pagar` solo confirma la reserva si queda pagada'],
    ['RN7', 'Las temporadas de un año no se cruzan, y cada noche tiene exactamente una tarifa por habitación',
     'Disparador `trg_temporada_sin_cruce` (ORA-20014); PK compuesta de TARIFA; `fn_valor_estadia` (ORA-20006/-20007)'],
    ['RN8', 'Un encargado solo gestiona las tarifas y reservas de los alojamientos que tiene asignados',
     'USUARIO_ALOJAMIENTO, `USUARIO_SISTEMA.usuario_bd` y las vistas `V_ADMIN_MIS_TARIFAS` y `V_ADMIN_MIS_RESERVAS` (script 09)'],
])

# ============================================================== 3. MODELO
c = replace_par(55)
c.para('La Figura 1 es el MER en notación de Chen de la Entrega 1, que la docente evaluó como «muy bueno»: '
       'rectángulos para entidades (doble para las débiles), rombos para relaciones, óvalos para atributos, '
       'cardinalidad 1/N junto a cada entidad y participación total con línea doble. La Figura 2 lo complementa '
       'con las entidades y atributos que se agregaron en las Entregas 2 y 3.')
c.image(os.path.join(IMG, 'mer_chen.png'), 16.5)
c.caption('Figura 1. MER de TurismoUQ en notación de Chen (16 entidades de la Entrega 1)')
c.image(os.path.join(IMG, 'mer_agregadas.png'), 16.5)
c.caption('Figura 2. Entidades y atributos agregados en las Entregas 2 y 3')
fill_table(tbl(57), [
    ['1', 'MUNICIPIO', 'Obligatoria', 'municipio_id', 'Los 12 municipios del Quindío'],
    ['2', 'TIPO_ALOJAMIENTO', 'Obligatoria', 'tipo_alojamiento_id', 'Finca cafetera, hotel, glamping, hostal'],
    ['3', 'ALOJAMIENTO', 'Obligatoria', 'alojamiento_id', 'Establecimiento: nombre, dirección, estrellas y contacto'],
    ['4', 'HABITACION', 'Obligatoria', 'habitacion_id', 'Unidad rentable: número (único en su alojamiento), capacidad y tipo'],
    ['5', 'TEMPORADA', 'Obligatoria', 'temporada_id', 'Periodo ALTA/MEDIA/BAJA de un año con su rango de fechas'],
    ['6', 'TARIFA', 'Obligatoria (débil)', 'habitacion_id + temporada_id', 'Precio por noche de una habitación en una temporada'],
    ['7', 'CLIENTE', 'Obligatoria', 'cliente_id', 'Persona que reserva; documento y correo únicos'],
    ['8', 'RESERVA', 'Obligatoria', 'reserva_id', 'Cabecera: cliente, rango de fechas, estado y fecha de cancelación'],
    ['9', 'RESERVA_HABITACION', 'Obligatoria', 'reserva_habitacion_id', 'Línea de reserva: habitación, fechas propias y huéspedes'],
    ['10', 'PAGO', 'Obligatoria', 'pago_id', 'Pago, abono o reembolso con método y estado'],
    ['11', 'SERVICIO', 'Obligatoria', 'servicio_id', 'Servicio complementario propio de un alojamiento'],
    ['12', 'RESERVA_SERVICIO', 'Obligatoria', 'reserva_servicio_id', 'Servicio contratado en una reserva, con cantidad'],
    ['13', 'RESENA', 'Obligatoria', 'resena_id', 'Calificación 1-5 y comentario de una estadía completada'],
    ['14', 'USUARIO_SISTEMA', 'Obligatoria', 'usuario_id', 'Usuario interno con su rol y su cuenta de base de datos'],
    ['15', 'ROL', 'Agregada', 'rol_id', 'Separa el rol del usuario para no repetirlo como texto'],
    ['16', 'USUARIO_ALOJAMIENTO', 'Agregada (débil)', 'usuario_id + alojamiento_id', 'Un encargado atiende varios alojamientos y viceversa'],
    ['17', 'LIQUIDACION_MENSUAL', 'Agregada', 'liquidacion_id', 'Resultado del cursor de liquidación mensual (Entrega 2)'],
    ['18', 'AUDITORIA_TARIFA', 'Agregada', 'auditoria_id', 'Quién, cuándo, valor anterior y nuevo de cada cambio de tarifa (Entrega 2)'],
    ['19', 'RESERVA_HISTORICO', 'Agregada', 'reserva_id', 'Reservas cerradas en su propio tablespace (Entrega 2)'],
    ['20', 'CALENDARIO', 'Agregada', 'fecha', 'Un día por fila; reparte las noches por mes para la vista materializada'],
])

c = replace_par(60)
c.para('La Figura 3 muestra las 20 tablas con sus llaves primarias (PK), foráneas (FK) y únicas (UK). Cada relación '
       '1:N se resolvió con una FK en el lado N; la relación 1:1 entre reserva y reseña, con una FK única en RESENA; '
       'y las entidades débiles con llave compuesta. AUDITORIA_TARIFA no tiene FK a propósito: la auditoría debe '
       'sobrevivir aunque la tarifa se borre.')
c.image(os.path.join(IMG, 'relacional.png'), 16.5)
c.caption('Figura 3. Modelo relacional de TurismoUQ (20 tablas)')

c = replace_par(62)
c.para('El modelo cambió después de la retroalimentación de la Entrega 1 y para soportar las Entregas 2 y 3:')
fill_table(tbl(63), [
    ['UNIQUE en CLIENTE.correo', 'Observación de la docente en la Entrega 1', '01_ddl.sql'],
    ['TEMPORADA cubre todos los días de 2024 a 2027 (10 por año) y tiene CHECK de año', 'La Entrega 1 dejaba 2024 y 371 días de 2025-2026 sin temporada', '01_ddl.sql, 02_carga.sql'],
    ['RESERVA_HABITACION.num_huespedes', 'sp_crear_reserva valida la capacidad de la habitación (RN5)', '01_ddl.sql'],
    ['RESERVA.fecha_cancelacion con CHECK de coherencia con el estado', 'La regla de reembolso depende de cuándo se canceló (RN1)', '01_ddl.sql, 04_paquete.sql'],
    ['USUARIO_SISTEMA.usuario_bd (UNIQUE)', 'Las vistas de seguridad filtran por el usuario conectado (RN8)', '01_ddl.sql, 09_seguridad.sql'],
    ['SERVICIO: UNIQUE (alojamiento_id, nombre)', 'Un alojamiento no repite un servicio con el mismo nombre', '01_ddl.sql'],
    ['Tablas LIQUIDACION_MENSUAL, AUDITORIA_TARIFA, RESERVA_HISTORICO y CALENDARIO', 'Las exigen el cursor, el disparador de auditoría, el tablespace y la vista materializada', '04, 05 y 06'],
    ['COMMENT ON TABLE en todas las tablas', 'El enunciado pide comentar cada tabla', '01_ddl.sql'],
])

# ============================================================== 4.1 DICCIONARIO
DIC = [
 ('MUNICIPIO', 'los 12 municipios del Quindío', [
   ('municipio_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('nombre', 'VARCHAR2(100)', 'No', '', 'UNIQUE', 'Nombre del municipio')]),
 ('TIPO_ALOJAMIENTO', 'clasificación de los alojamientos', [
   ('tipo_alojamiento_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('nombre', 'VARCHAR2(50)', 'No', '', 'UNIQUE', 'FINCA_CAFETERA, HOTEL, GLAMPING, HOSTAL')]),
 ('ROL', 'perfil de permisos de un usuario interno', [
   ('rol_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('nombre', 'VARCHAR2(50)', 'No', '', 'UNIQUE', 'ADMINISTRADOR, ENCARGADO_ALOJAMIENTO')]),
 ('ALOJAMIENTO', 'establecimiento que ofrece habitaciones', [
   ('alojamiento_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('municipio_id', 'NUMBER', 'No', 'FK', '→ MUNICIPIO', 'Municipio donde está'),
   ('tipo_alojamiento_id', 'NUMBER', 'No', 'FK', '→ TIPO_ALOJAMIENTO', 'Tipo de alojamiento'),
   ('nombre_comercial', 'VARCHAR2(150)', 'No', '', '', 'Nombre comercial'),
   ('direccion', 'VARCHAR2(200)', 'No', '', '', 'Dirección'),
   ('calificacion_estrellas', 'NUMBER(1)', 'No', '', 'CHECK 1 a 5', 'Estrellas autoasignadas'),
   ('telefono', 'VARCHAR2(30)', 'Sí', '', '', 'Teléfono de contacto'),
   ('correo', 'VARCHAR2(100)', 'Sí', '', '', 'Correo de contacto')]),
 ('HABITACION', 'unidad rentable de un alojamiento', [
   ('habitacion_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('alojamiento_id', 'NUMBER', 'No', 'FK', '→ ALOJAMIENTO; UNIQUE con numero', 'Alojamiento al que pertenece'),
   ('numero', 'VARCHAR2(10)', 'No', '', 'UNIQUE (alojamiento_id, numero)', 'Número dentro del alojamiento'),
   ('capacidad_maxima', 'NUMBER', 'No', '', 'CHECK > 0', 'Máximo de huéspedes'),
   ('tipo_habitacion', 'VARCHAR2(30)', 'No', '', 'CHECK SENCILLA/DOBLE/SUITE/CABANA', 'Tipo de habitación'),
   ('descripcion', 'VARCHAR2(500)', 'Sí', '', '', 'Descripción')]),
 ('TEMPORADA', 'periodo de precios de un año', [
   ('temporada_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('nombre', 'VARCHAR2(100)', 'No', '', 'UNIQUE (nombre, anio)', 'Ej.: Semana Santa'),
   ('categoria', 'VARCHAR2(10)', 'No', '', 'CHECK ALTA/MEDIA/BAJA', 'Categoría'),
   ('anio', 'NUMBER(4)', 'No', '', 'CHECK fechas dentro del año', 'Año de la temporada'),
   ('fecha_inicio', 'DATE', 'No', '', '', 'Primer día'),
   ('fecha_fin', 'DATE', 'No', '', 'CHECK fecha_fin >= fecha_inicio', 'Último día')]),
 ('TARIFA', 'precio por noche de una habitación en una temporada', [
   ('habitacion_id', 'NUMBER', 'No', 'PK, FK', '→ HABITACION', 'Habitación'),
   ('temporada_id', 'NUMBER', 'No', 'PK, FK', '→ TEMPORADA', 'Temporada'),
   ('precio_noche', 'NUMBER(10,2)', 'No', '', 'CHECK > 0', 'Precio de una noche')]),
 ('CLIENTE', 'persona que reserva', [
   ('cliente_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('nombre', 'VARCHAR2(150)', 'No', '', '', 'Nombre completo'),
   ('documento_identidad', 'VARCHAR2(30)', 'No', '', 'UNIQUE', 'Documento'),
   ('correo', 'VARCHAR2(100)', 'No', '', 'UNIQUE', 'Correo'),
   ('telefono', 'VARCHAR2(30)', 'Sí', '', '', 'Teléfono'),
   ('ciudad_origen', 'VARCHAR2(100)', 'Sí', '', '', 'Ciudad de origen')]),
 ('RESERVA', 'cabecera de la reserva', [
   ('reserva_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('cliente_id', 'NUMBER', 'No', 'FK', '→ CLIENTE', 'Cliente que reserva'),
   ('fecha_checkin', 'DATE', 'No', '', '', 'Inicio del rango general'),
   ('fecha_checkout', 'DATE', 'No', '', 'CHECK > fecha_checkin', 'Fin del rango general'),
   ('fecha_reserva', 'DATE', 'No', '', 'DEFAULT SYSDATE', 'Cuándo se hizo la reserva'),
   ('estado', 'VARCHAR2(15)', 'No', '', 'CHECK PENDIENTE/CONFIRMADA/CANCELADA/COMPLETADA', 'Estado'),
   ('fecha_cancelacion', 'DATE', 'Sí', '', 'CHECK: obligatoria solo si CANCELADA', 'Cuándo se canceló (RN1)')]),
 ('RESERVA_HABITACION', 'línea de reserva', [
   ('reserva_habitacion_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('reserva_id', 'NUMBER', 'No', 'FK', '→ RESERVA; UNIQUE con habitación y check-in', 'Reserva'),
   ('habitacion_id', 'NUMBER', 'No', 'FK', '→ HABITACION', 'Habitación tomada'),
   ('fecha_checkin', 'DATE', 'No', '', '', 'Llegada de esta habitación'),
   ('fecha_checkout', 'DATE', 'No', '', 'CHECK > fecha_checkin', 'Salida de esta habitación'),
   ('num_huespedes', 'NUMBER(2)', 'No', '', 'CHECK > 0; DEFAULT 1', 'Huéspedes en la habitación')]),
 ('PAGO', 'pago, abono o reembolso de una reserva', [
   ('pago_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('reserva_id', 'NUMBER', 'No', 'FK', '→ RESERVA', 'Reserva pagada'),
   ('fecha_pago', 'DATE', 'No', '', 'DEFAULT SYSDATE', 'Fecha del pago'),
   ('monto', 'NUMBER(12,2)', 'No', '', 'CHECK > 0', 'Valor'),
   ('metodo', 'VARCHAR2(20)', 'No', '', 'CHECK 5 métodos', 'Tarjeta crédito/débito, PSE, transferencia, efectivo'),
   ('estado', 'VARCHAR2(15)', 'No', '', 'CHECK EXITOSO/FALLIDO/PENDIENTE/REEMBOLSADO', 'Estado del pago')]),
 ('SERVICIO', 'servicio complementario de un alojamiento', [
   ('servicio_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('alojamiento_id', 'NUMBER', 'No', 'FK', '→ ALOJAMIENTO; UNIQUE con nombre', 'Alojamiento que lo ofrece'),
   ('nombre', 'VARCHAR2(100)', 'No', '', 'UNIQUE (alojamiento_id, nombre)', 'Nombre'),
   ('descripcion', 'VARCHAR2(500)', 'Sí', '', '', 'Descripción'),
   ('precio', 'NUMBER(10,2)', 'No', '', 'CHECK >= 0', 'Precio por unidad')]),
 ('RESERVA_SERVICIO', 'servicio contratado en una reserva', [
   ('reserva_servicio_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('reserva_id', 'NUMBER', 'No', 'FK', '→ RESERVA; UNIQUE con servicio', 'Reserva'),
   ('servicio_id', 'NUMBER', 'No', 'FK', '→ SERVICIO', 'Servicio'),
   ('cantidad', 'NUMBER', 'No', '', 'CHECK > 0', 'Unidades contratadas')]),
 ('RESENA', 'calificación de una estadía completada', [
   ('resena_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('cliente_id', 'NUMBER', 'No', 'FK', '→ CLIENTE', 'Autor'),
   ('alojamiento_id', 'NUMBER', 'No', 'FK', '→ ALOJAMIENTO', 'Alojamiento reseñado'),
   ('reserva_id', 'NUMBER', 'No', 'FK', '→ RESERVA; UNIQUE', 'Estadía que la origina (RN2)'),
   ('calificacion', 'NUMBER(1)', 'No', '', 'CHECK 1 a 5', 'Estrellas'),
   ('comentario', 'VARCHAR2(1000)', 'Sí', '', '', 'Comentario opcional'),
   ('fecha', 'DATE', 'No', '', 'DEFAULT SYSDATE', 'Fecha')]),
 ('USUARIO_SISTEMA', 'usuario interno de la plataforma', [
   ('usuario_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('rol_id', 'NUMBER', 'No', 'FK', '→ ROL', 'Rol'),
   ('nombre', 'VARCHAR2(150)', 'No', '', '', 'Nombre'),
   ('correo', 'VARCHAR2(100)', 'No', '', 'UNIQUE', 'Correo'),
   ('clave_hash', 'VARCHAR2(255)', 'No', '', '', 'Hash SHA-256 de la clave'),
   ('usuario_bd', 'VARCHAR2(30)', 'Sí', '', 'UNIQUE; CHECK en mayúsculas', 'Cuenta de base de datos (RN8)')]),
 ('USUARIO_ALOJAMIENTO', 'asignación de encargados a alojamientos', [
   ('usuario_id', 'NUMBER', 'No', 'PK, FK', '→ USUARIO_SISTEMA', 'Encargado'),
   ('alojamiento_id', 'NUMBER', 'No', 'PK, FK', '→ ALOJAMIENTO', 'Alojamiento asignado')]),
 ('LIQUIDACION_MENSUAL', 'resultado del proceso de liquidación', [
   ('liquidacion_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('alojamiento_id', 'NUMBER', 'No', 'FK', '→ ALOJAMIENTO; UNIQUE con anio y mes', 'Alojamiento liquidado'),
   ('anio, mes', 'NUMBER(4), NUMBER(2)', 'No', '', 'CHECK mes 1 a 12', 'Periodo'),
   ('num_reservas, noches_vendidas', 'NUMBER', 'No', '', '', 'Actividad del mes'),
   ('valor_hospedaje, valor_servicios, valor_bruto', 'NUMBER(14,2)', 'No', '', '', 'Valores del mes'),
   ('pct_comision', 'NUMBER(5,4)', 'No', '', '', 'Comisión aplicada'),
   ('valor_comision, valor_neto', 'NUMBER(14,2)', 'No', '', '', 'Comisión y neto para el alojamiento'),
   ('fecha_proceso, usuario_proceso', 'DATE, VARCHAR2(128)', 'No', '', '', 'Quién y cuándo liquidó')]),
 ('AUDITORIA_TARIFA', 'cambios en TARIFA', [
   ('auditoria_id', 'NUMBER', 'No', 'PK', 'IDENTITY', 'Identificador'),
   ('id_sentencia', 'NUMBER', 'No', '', 'SEQ_AUDITORIA_SENTENCIA', 'Agrupa las filas de una sentencia'),
   ('operacion', 'VARCHAR2(6)', 'No', '', 'CHECK INSERT/UPDATE/DELETE', 'Operación'),
   ('habitacion_id, temporada_id', 'NUMBER', 'No', '', 'sin FK a propósito', 'Tarifa afectada'),
   ('precio_anterior, precio_nuevo', 'NUMBER(10,2)', 'Sí', '', '', 'Valor anterior y nuevo'),
   ('usuario_bd, usuario_so, equipo, programa', 'VARCHAR2(128)', 'usuario_bd No', '', '', 'Quién hizo el cambio'),
   ('fecha_hora', 'TIMESTAMP', 'No', '', '', 'Cuándo')]),
 ('RESERVA_HISTORICO', 'reservas cerradas, en TS_TURISMO_HISTORICO', [
   ('reserva_id', 'NUMBER', 'No', 'PK', 'índice en TS_TURISMO_HISTORICO', 'Reserva archivada'),
   ('cliente_id, alojamiento_id', 'NUMBER', 'cliente No', '', '', 'Copia desnormalizada'),
   ('alojamiento, municipio', 'VARCHAR2', 'Sí', '', '', 'Nombres al momento de archivar'),
   ('fecha_reserva, fecha_checkin, fecha_checkout', 'DATE', 'No', '', '', 'Fechas'),
   ('estado', 'VARCHAR2(15)', 'No', '', 'CHECK COMPLETADA/CANCELADA', 'Estado final'),
   ('num_habitaciones, noches_habitacion', 'NUMBER', 'No', '', '', 'Tamaño de la reserva'),
   ('total_pagado', 'NUMBER(14,2)', 'No', '', '', 'Exitosos menos reembolsos'),
   ('fecha_archivo', 'DATE', 'No', '', '', 'Cuándo se archivó')]),
 ('CALENDARIO', 'un día por fila (2024-2027)', [
   ('fecha', 'DATE', 'No', 'PK', '', 'Día'),
   ('anio, mes, dia', 'NUMBER', 'No', '', '', 'Partes de la fecha')]),
]
p = E[68]
tdic = E[69]
c = replace_par(67)
c.para('Las 20 tablas del esquema TURISMOUQ. Las restricciones coinciden con `01_ddl.sql` y, para las cuatro '
       'tablas de las Entregas 2 y 3, con los scripts 04, 05 y 06. Todo valor de dinero es NUMBER(p,s).')
# se quitan el titulo y la tabla de ejemplo de la plantilla y se generan las 20
anchor = c.last
p.getparent().remove(p)
tdic.getparent().remove(tdic)
c = Cursor(anchor)
for name, desc, cols in DIC:
    c.add(p_xml(run_xml('Tabla: ', bold=True) + run_xml(f'{name} — {desc}'), before=160, after=60, jc='left', keep_next=True))
    c.add(table_xml(['Columna', 'Tipo de dato', '¿Nulo?', 'PK / FK', 'Restricción', 'Descripción'],
                    cols, [1900, 1500, 700, 800, 2115, 2000], 18))

E[71].getparent().remove(E[71])   # instruccion de la plantilla ("Recuerden: ...")

# ============================================================== 4.2 VOLUMEN
c = replace_par(73)
c.para('Conteos tomados con `SELECT COUNT(*)` en una base limpia, justo después de `02_carga.sql` (el script los '
       'imprime al final; `demo/datos_para_documento.sql` los vuelve a sacar).')
c.placeholder('Insertar captura de los conteos en SQL Developer')
vol = [('MUNICIPIO', 12), ('TIPO_ALOJAMIENTO', 4), ('ALOJAMIENTO', 60), ('HABITACION', 400), ('TEMPORADA', 6),
       ('TARIFA', None), ('CLIENTE', 3000), ('RESERVA', 25000), ('RESERVA_HABITACION', 25000), ('PAGO', 25000),
       ('SERVICIO', 30), ('RESERVA_SERVICIO', 40000), ('RESENA', None), ('USUARIO_SISTEMA', 10)]
rows = []
for name, mn in vol:
    val = v('n_' + name, 'conteo')
    if name == 'TARIFA':
        val = v('n_TARIFA', 'conteo') + ' = ' + v('n_HABITACION', 'hab.') + ' × 40'
    if name == 'RESENA':
        val = v('n_RESENA', 'conteo') + ' (' + v('pct_resena', '%') + ' % de las completadas)'
    if name == 'TEMPORADA':
        val = v('n_TEMPORADA', 'conteo') + ' (10 por año, 2024-2027)'
    rows.append([None, None, val, 'Sí' if ('[[' not in val) else v('cumple_' + name, 'Sí/No')])
fill_table(tbl(74), rows)

c = replace_par(77)
c.para('Los datos se generaron con PL/SQL y `DBMS_RANDOM` con semilla fija (`DBMS_RANDOM.SEED(20261022)`), así que '
       'son reproducibles. La asimetría es intencional: cada municipio tiene un peso distinto (Armenia 14 '
       'alojamientos, Buenavista y Córdoba 1) y un tipo dominante; las habitaciones dependen del tipo (hoteles 20-40, '
       'fincas 3-8); las reservas se reparten por mes con pesos que generan picos en enero, Semana Santa, mitad de '
       'año y diciembre; los montos de pago salen de TARIFA, y antes de asignar una habitación se revisa día por día '
       'que esté libre.')
fill_table(tbl(78), [
    [None, v('alojxmun_min', 'mín.'), v('alojxmun_max', 'máx.')],
    [None, v('habxaloj_min', 'mín.'), v('habxaloj_max', 'máx.')],
    [None, v('resxmes_min', 'mín.'), v('resxmes_max', 'máx.')],
    [None, v('res_varias_hab', 'cantidad'), '1 a 3 habitaciones por reserva'],
    [None, v('res_varios_pagos', 'cantidad'), 'Anticipo + saldo, o anticipo + reembolso'],
])

# ============================================================== 5. CONSULTAS
def consulta(n, end_marker):
    a = QRY.index(f'-- CONSULTA {n}.')
    a = QRY.rfind('-- =====', 0, a)
    b = QRY.index(end_marker, a) + len(end_marker)
    return QRY[a:b].strip('\n')


fill_table(tbl(82), [
    [None, None, None, v('filas_C1', 'filas')],
    [None, None, None, v('filas_C2', 'filas')],
    [None, None, None, v('filas_C3', 'filas')],
    [None, None, None, v('filas_C4', 'filas')],
    [None, '¿Cuántas reservas hubo y cuánto se recaudó por municipio entre dos fechas?', 'Variables de enlace', v('filas_C5', 'filas')],
    [None, '¿Cuántas reservas se crean, llegan y salen cada mes?', 'UNPIVOT', v('filas_C6', 'filas')],
    [None, '¿Qué tipo de alojamiento está mejor calificado por los huéspedes?', 'Libre', v('filas_C7', 'filas')],
])

QDATA = [
 (85, 1, 'ORDER BY municipio;',
  '¿Cuántas noches-habitación se vendieron en cada municipio, mes a mes, durante 2025?',
  'Muestra en una sola tabla la estacionalidad de cada municipio: las columnas de enero, junio-julio y diciembre '
  'concentran las noches vendidas, y los municipios con más oferta hotelera (Armenia) y turística (Salento, '
  'Filandia) dominan el volumen. A la gerencia le dice cuándo y dónde reforzar personal y promoción.'),
 (87, 2, 'ORDER BY mu.nombre, ta.nombre, t.anio, MIN(t.fecha_inicio);',
  '¿Cuánto ingresa cada municipio, por tipo de alojamiento y por temporada (con su año), con subtotales?',
  'Cada municipio tiene su subtotal por tipo y su subtotal general, y la última fila es el total de la plataforma. '
  'Como la temporada se agrupa con su año, Semana Santa 2025 y 2026 se comparan por separado. El ingreso es neto: '
  'pagos exitosos menos reembolsos, y ningún pago queda por fuera porque las temporadas cubren todos los días.'),
 (89, 3, 'ORDER BY municipio, posicion;',
  '¿Cuáles son los 3 alojamientos de mayor ingreso dentro de cada municipio?',
  'RANK reinicia la posición en cada municipio, así que la gerencia ve el podio local y no solo el nacional: en '
  'municipios con pocos alojamientos el top 3 casi los cubre a todos, mientras que en Armenia o Salento la '
  'diferencia entre el primero y el tercero muestra qué tan concentrado está el ingreso.'),
 (91, 4, 'ORDER BY mes;',
  '¿Cuánto varía el ingreso de un mes respecto al mes anterior?',
  'LAG trae el ingreso del mes anterior a la misma fila, y la variación porcentual marca las subidas al entrar a '
  'temporada alta y las caídas al salir de ella. Sirve para presupuestar la caja y anticipar los meses flojos.'),
 (93, 5, 'ORDER BY ingreso_total DESC;',
  '¿Cuántas reservas hubo y cuánto se recaudó por municipio entre dos fechas que elige el usuario?',
  'Las fechas son variables de enlace declaradas con VARIABLE y asignadas con EXEC: para otro rango solo se '
  'cambian los dos EXEC y Oracle reutiliza el mismo plan. En el ejemplo (temporada de mitad de año 2025) se ve qué '
  'municipios aprovechan mejor la temporada.'),
 (95, 6, 'ORDER BY mes, tipo_evento;',
  '¿Cuánta actividad operativa hay cada mes: reservas que se crean, huéspedes que llegan y huéspedes que salen?',
  'UNPIVOT convierte las tres columnas reales de fecha de RESERVA en filas (tipo de evento, fecha). Recepción ve '
  'que las reservas se crean semanas antes de los picos de llegadas: sirve para planear el personal de cada mes.'),
 (97, 7, 'ORDER BY calificacion_promedio DESC;',
  '¿Qué tipo de alojamiento (finca, hotel, glamping, hostal) tiene mejor calificación de los huéspedes?',
  'El promedio va acompañado del número de alojamientos y de reseñas que lo respaldan, porque un promedio con '
  'pocas reseñas no es confiable. Ayuda a decidir en qué tipo de alojamiento invertir o qué promocionar.'),
]
set_par(96, '5.7 C7 — Consulta libre: calificación por tipo de alojamiento')
for idx, n, endm, pregunta, lectura in QDATA:
    c = replace_par(idx)
    c.para('**Pregunta de negocio.** ' + pregunta)
    c.code(consulta(n, endm))
    c.placeholder(f'Insertar captura del resultado de C{n} en SQL Developer')
    c.para('**Lectura para la gerencia.** ' + lectura)

# ============================================================== 6. PL/SQL
c = replace_par(100)
c.para('Todo el código PL/SQL de la Entrega 2 vive en el paquete `PKG_TURISMO` (`04_paquete.sql`). La '
       'especificación expone las funciones, los procedimientos y las excepciones propias; las excepciones se '
       'asocian a sus códigos con `PRAGMA EXCEPTION_INIT`, así que quien llama puede atraparlas por nombre '
       '(`WHEN pkg_turismo.e_capacidad_excedida`). En el cuerpo quedan privadas `fmt` (formato de fechas para los '
       'mensajes) y `validar_linea` (validaciones comunes de una línea de reserva): nadie fuera del paquete '
       'necesita llamarlas.')
c.code(between(PKG, 'CREATE OR REPLACE PACKAGE pkg_turismo AS', 'END pkg_turismo;'), size=14)
fill_table(tbl(101), [
    [None, None, 'Función', 'Valor de una habitación noche por noche con la tarifa de cada temporada que atraviesa'],
    [None, None, 'Procedimiento', 'Crea reserva y línea; valida fechas, cliente, habitación, capacidad y disponibilidad; bloquea la habitación'],
    [None, 'sp_liquidacion_mensual', 'Procedimiento con cursor', 'Recorre el cursor c_liquidacion(cp_inicio, cp_fin, cp_alojamiento); guarda y reporta la liquidación'],
    ['Valor total de una reserva', 'fn_valor_reserva', 'Función', 'Estadía de todas las líneas más servicios'],
    ['Total pagado / pagada', 'fn_total_pagado, fn_reserva_pagada', 'Funciones', 'Pagos exitosos menos reembolsos; ‘S’ si cubre el total (RN6)'],
    ['Reserva de grupo', 'sp_agregar_habitacion', 'Procedimiento', 'Agrega otra habitación del mismo alojamiento dentro del rango (RN4)'],
    ['Cancelación', 'sp_cancelar_reserva', 'Procedimiento', 'Cancela y aplica el reembolso del 80 % con más de 5 días (RN1)'],
])

c = replace_par(104)
c.para('**Algoritmo.** La función recorre las noches desde `fecha_in` hasta `fecha_out - 1`. Guarda en `v_ini`, '
       '`v_fin` y `v_precio` la temporada vigente; mientras la noche esté dentro de ese rango suma `v_precio` sin '
       'consultar la base, y cuando la noche se sale de él (la estadía cruzó a otra temporada) busca la nueva '
       'temporada y su tarifa con una sola consulta. Una estadía que cruza dos temporadas hace dos consultas, no '
       'una por noche. Valida las fechas (ORA-20002) y la habitación (ORA-20005); si una noche no tiene temporada '
       'lanza ORA-20006 y si cae en dos, ORA-20007.')
c.code(between(PKG, '    -- ========================================================================\n    -- fn_valor_estadia', 'END fn_valor_estadia;'), size=14)
c.para('El valor esperado se calcula a mano, noche por noche, con las tarifas de la habitación 1 (salen con '
       '`demo/datos_para_documento.sql`). La prueba P1.2 de `10_pruebas.sql` hace además la comparación con un '
       'cálculo independiente en SQL para siete casos, incluido 2024.')
fill_table(tbl(105), [
    ['Una sola temporada', '1', '05/10/2026', '08/10/2026', 'Temporada media III 2026 (3 noches)',
     '3 × ' + v('t_media3_2026', 'tarifa') + ' = ' + v('esp_1', 'valor'), v('fn_1', 'valor')],
    ['Cruza dos temporadas', '1', '28/11/2026', '03/12/2026', 'Media III 2026 (28, 29, 30 nov) y Fin de año 2026 (1, 2 dic)',
     '3 × ' + v('t_media3_2026', 'tarifa') + ' + 2 × ' + v('t_fin_2026', 'tarifa') + ' = ' + v('esp_2', 'valor'), v('fn_2', 'valor')],
    ['Cruza el cambio de año', '1', '29/12/2026', '03/01/2027', 'Fin de año 2026 (29, 30, 31) e Inicio de año 2027 (1, 2 ene)',
     '3 × ' + v('t_fin_2026', 'tarifa') + ' + 2 × ' + v('t_ini_2027', 'tarifa') + ' = ' + v('esp_3', 'valor'), v('fn_3', 'valor')],
    ['Fechas inválidas', '1', '10/12/2026', '10/12/2026', '—', 'ORA-20002', 'ORA-20002: El check-out (10/12/2026) debe ser posterior al check-in (10/12/2026).'],
])

c = replace_par(108)
c.para('El procedimiento valida en este orden: estado inicial, cliente (ORA-20004), fechas (ORA-20002), huéspedes '
       '(ORA-20008), habitación (ORA-20005, y la bloquea con `SELECT ... FOR UPDATE`), capacidad (ORA-20003) y '
       'disponibilidad contra las reservas activas (ORA-20001). Calcula el valor antes de insertar, para que una '
       'tarifa faltante no deje nada a medias, y no hace COMMIT: la transacción la confirma quien lo llama.')
c.code(between(PKG, '    PROCEDURE validar_linea (', 'END validar_linea;') + '\n\n' +
       between(PKG, '    PROCEDURE sp_crear_reserva (', 'END sp_crear_reserva;', after='END validar_linea;'), size=14)
fill_table(tbl(109), [
    [None, '-20001', 'Habitacion no disponible: la habitacion N ya esta reservada entre el 01/12/2026 y el 04/12/2026 (se cruza con la reserva R).',
     "sp_crear_reserva(:cli, :hab, DATE '2026-12-01', DATE '2026-12-04', 1, ...) sobre una habitación ya reservada (P2.2)"],
    [None, '-20002', 'Fechas invalidas: el check-out (10/12/2026) es anterior o igual al check-in (10/12/2026).',
     "sp_crear_reserva(:cli, :hab, DATE '2026-12-10', DATE '2026-12-10', 1, ...) (P2.3 y P2.4)"],
    [None, '-20003', 'Capacidad excedida: la habitacion N admite C huesped(es) y se pidieron C+1.',
     "sp_crear_reserva(:cli, :hab, DATE '2026-12-10', DATE '2026-12-12', :cap + 1, ...) (P2.5)"],
    [None, '—', 'OK reserva creada: R valor estadia: V (= fn_valor_estadia)',
     "sp_crear_reserva(:cli, :hab, DATE '2026-11-28', DATE '2026-12-03', 2, ..., 'CONFIRMADA') (P2.1)"],
])
c = Cursor(E[109].getnext())
c.para('Las otras excepciones propias también se prueban en P2.6 a P2.8: cliente inexistente (ORA-20004), '
       'habitación inexistente (ORA-20005), estado inicial inválido (ORA-20012), habitación de otro alojamiento en '
       'una reserva de grupo (ORA-20010) y línea fuera del rango de la reserva (ORA-20002).')
c.placeholder('Insertar captura de las pruebas P2.1 a P2.5 (salida de 10_pruebas.sql)')

c = replace_par(112)
c.para('`sp_liquidacion_mensual(p_anio, p_mes, p_alojamiento_id, p_pct_comision)` calcula el periodo '
       '`[primer día del mes, primer día del mes siguiente)` y recorre con `OPEN`, `FETCH` y `CLOSE` el cursor '
       'explícito `c_liquidacion(cp_inicio, cp_fin, cp_alojamiento)`. Con `cp_alojamiento` en NULL liquida todos los '
       'alojamientos; con un valor, solo ese. Por cada alojamiento el cursor entrega:')
c.bullets([
    'las noches vendidas **dentro del mes** (una estadía del 30/01 al 02/02 aporta 2 noches a enero y 1 a febrero);',
    'el valor del hospedaje de esas noches, con `fn_valor_estadia` sobre el tramo recortado al mes;',
    'el valor de los servicios de las reservas con check-in en el mes.',
])
c.para('Solo cuentan las reservas CONFIRMADA o COMPLETADA. El procedimiento calcula la comisión (10 % por defecto) y '
       'el neto, guarda una fila por alojamiento en LIQUIDACION_MENSUAL (reprocesar un mes reemplaza el anterior) e '
       'imprime el reporte. Como es un proceso masivo independiente, hace COMMIT.')
c.code(between(PKG, '        CURSOR c_liquidacion (cp_inicio DATE', 'ORDER BY mu.nombre, a.nombre_comercial;') + '\n    ...\n' +
       between(PKG, '        OPEN c_liquidacion(v_inicio, v_fin, p_alojamiento_id);', 'CLOSE c_liquidacion;'), size=14)
c.para('**Corrida de julio de 2025** (`EXEC pkg_turismo.sp_liquidacion_mensual(2025, 7);`): liquidó '
       + v('liq_aloj', 'N') + ' alojamientos, ' + v('liq_noches', 'N') + ' noches y un valor bruto de '
       + v('liq_bruto', '$') + ' (comisión ' + v('liq_comision', '$') + ', neto ' + v('liq_neto', '$') + '). Las '
       'noches coinciden con la vista materializada y el hospedaje con un cálculo noche a noche independiente (P3.3).')
c.placeholder('Insertar captura del reporte de la liquidación')

c = replace_par(114)
c.para('**Cómo se resolvió que un disparador de sentencia no ve :OLD ni :NEW.** `trg_tarifa_auditoria` es un '
       '*compound trigger*: sus secciones de sentencia y de fila comparten variables. `BEFORE STATEMENT` numera la '
       'sentencia con `SEQ_AUDITORIA_SENTENCIA` y toma quién (usuario de base de datos, usuario del sistema '
       'operativo, equipo, programa) y cuándo (`SYSTIMESTAMP`); `AFTER EACH ROW` solo copia `:OLD` y `:NEW` a una '
       'colección en memoria; y `AFTER STATEMENT` escribe toda la auditoría con un solo `FORALL`. Un UPDATE que cambia '
       '37 tarifas produce 37 filas con el mismo `id_sentencia` y la misma hora.')
c.para('**Corrección tras la Entrega 2: comparación contra NULL.** Un UPDATE solo se audita si algo cambió, y la '
       'comparación se hace con la función `distinto(a, b)`, que trata NULL como un valor más: (5, NULL) y '
       '(NULL, 5) cuentan como cambio y (NULL, NULL) no. Con un simple `a <> b`, cualquier comparación con NULL da '
       'NULL y el cambio no quedaba auditado. En INSERT el valor anterior queda NULL y en DELETE el nuevo.')
c.code(between(TRG, 'CREATE TABLE AUDITORIA_TARIFA (', 'END trg_tarifa_auditoria;'), size=14)
c.para('**Prueba (P5).** Un UPDATE de +5.000 sobre las 37 tarifas de un alojamiento en la temporada '
       '«Temporada media III 2027» (sin reservas), un UPDATE que deja el mismo precio (no audita filas), un DELETE '
       'y un INSERT de una tarifa, y al final el UPDATE que devuelve las tarifas a su valor. La consulta P5.5 muestra '
       'una fila por sentencia con quién y cuándo, y P5.6 el valor anterior y el nuevo de cada tarifa.')
c.placeholder('Insertar captura de P5.5 y P5.6 (auditoría por sentencia y detalle)')

c = replace_par(116)
c.para('**ORA-04091 y cómo se resolvió (corrección tras la Entrega 2).** La primera versión era un `BEFORE INSERT '
       '... FOR EACH ROW` que consultaba su propia tabla. Funcionaba con un `INSERT ... VALUES` de una fila, la única '
       'excepción que Oracle tolera, pero un `INSERT ... SELECT` o un `UPDATE` de varias filas habría fallado con '
       'ORA-04091 (tabla mutante). Ahora `trg_reshab_no_solape` es un disparador compuesto: `AFTER EACH ROW` solo '
       'anota el id de cada línea insertada o modificada, y `AFTER STATEMENT`, cuando la tabla ya no está mutando, '
       'busca para cada una otra línea activa de la misma habitación que se cruce. Si la encuentra, lanza ORA-20011 y '
       'Oracle deshace la sentencia completa.')
c.para('Dos rangos [ci, co) se cruzan si `nuevo.checkin < otro.checkout` y `nuevo.checkout > otro.checkin`; el día '
       'de check-out queda libre. Las líneas de reservas canceladas no ocupan la habitación.')
c.code(between(TRG, 'CREATE OR REPLACE TRIGGER trg_reshab_no_solape', 'END trg_reshab_no_solape;'), size=14)
c.para('**Prueba con casos reales (P6, inserciones directas en la tabla, sin pasar por el paquete):**')
c.table(['Caso', 'Resultado esperado'], [
    ['P6.2 INSERT ... VALUES que se solapa con una reserva confirmada', 'ORA-20011'],
    ['P6.4 Línea que entra el día en que sale la anterior', 'Se acepta'],
    ['P6.5 Línea de una reserva CANCELADA en las mismas fechas', 'Se acepta (no ocupa)'],
    ['P6.6 INSERT ... SELECT de dos filas, una se solapa', 'ORA-20011 (antes: ORA-04091); no entra ninguna de las dos'],
    ['P6.7 INSERT ... SELECT de dos filas sin solape', 'Se aceptan las dos'],
    ['P6.8 Dos líneas nuevas que se cruzan entre sí en la misma sentencia', 'ORA-20011'],
    ['P6.9 UPDATE que mueve una línea encima de otra reserva', 'ORA-20011'],
    ['P6.10 UPDATE a fechas libres', 'Se acepta'],
], [5600, 3415])
c.placeholder('Insertar captura de P6.2 (ORA-20011) y P6.6')

c = replace_par(118)
c.para('SYSTEM crea el tablespace en `00_usuario_y_tablespaces.sql` (crear un tablespace es un privilegio de '
       'administrador) con un datafile de 50 MB que crece de 10 en 10 MB hasta 1 GB, en la misma carpeta de los '
       'datafiles de la PDB (en el contenedor: `/opt/oracle/oradata/FREE/FREEPDB1/ts_turismo_historico01.dbf`). '
       'Allí viven la tabla `RESERVA_HISTORICO` (con `PCTFREE 0`) y su índice de llave primaria; '
       '`sp_archivar_reservas` copia las reservas cerradas (COMPLETADA o CANCELADA) antes de una fecha de corte. No se '
       'particionó RESERVA.')
c.code(between(USR, '-- 2. Tablespace del historico de reservas.', "END;\n/") , size=14)
c.para('**Por qué separarlo:**')
c.bullets([
    '**Patrón de acceso distinto.** RESERVA es OLTP: se inserta y actualiza todo el día. El histórico solo crece por cargas periódicas y se lee para reportes.',
    '**Crecimiento controlado.** Con su propio datafile y su MAXSIZE, si el histórico se llena no detiene las reservas nuevas del tablespace USERS.',
    '**Respaldo.** Puede ponerse en READ ONLY después de cada cierre anual: RMAN lo respalda una vez y la restauración del tablespace operativo no espera años de historia.',
    '**Ubicación física.** Su datafile puede moverse a un disco más barato sin afectar el rendimiento de las reservas.',
    '**Ajustes propios.** PCTFREE 0, porque las filas no se actualizan; cuotas y compresión distintas.',
])

c = replace_par(120)
c.para('`MV_OCUPACION_MENSUAL` tiene una fila por alojamiento y mes: noches disponibles (habitaciones × días del mes), '
       'noches vendidas (reservas CONFIRMADA o COMPLETADA, repartidas por mes con la tabla CALENDARIO) y porcentaje '
       'de ocupación. Incluye los meses sin ventas, para no inflar el promedio de los alojamientos pequeños. La '
       'prueba P8.4 la compara contra el cálculo en vivo (0 diferencias) y P8.5-P8.6 muestran que una reserva nueva '
       'no aparece hasta el refresco.')
c.code(between(MVS, 'CREATE MATERIALIZED VIEW MV_OCUPACION_MENSUAL', "       AND o.mes  = m.mes;"), size=14)
c.placeholder('Insertar captura de la ocupación 2025 por municipio leída de la vista (P8.2)')
fill_table(tbl(121), [
    [None, 'IMMEDIATE', 'Los datos ya están cargados cuando se crea; la gerencia la puede consultar enseguida.'],
    [None, 'COMPLETE', 'FAST no es posible: la consulta usa CROSS JOIN, LEFT JOIN contra subconsultas agregadas y un join por rango de fechas. Además, los logs de vista materializada encarecerían cada reserva.'],
    [None, 'ON DEMAND, programado cada noche a las 2:00 a.m. (DBMS_SCHEDULER) y manual al cerrar el mes',
     'ON COMMIT recalcularía la vista dentro de cada transacción de reserva. La ocupación mensual es un indicador de gerencia: un día de retraso es aceptable y a las 2:00 a.m. no compite con las reservas. atomic_refresh => TRUE: nunca se ve vacía.'],
])

# ============================================================== 7. ENTREGA 3
c = replace_par(125)
c.para('`sp_reservar_y_pagar` (`07_transacciones.sql`) registra reserva y pago en una sola transacción. Si falla la '
       'reserva, `ROLLBACK` total: no queda ni reserva ni pago. Si falla solo el pago (la pasarela lo rechaza o el '
       'INSERT viola una restricción), `ROLLBACK TO sp_reserva_creada`: se deshace solo el pago, la reserva queda '
       'PENDIENTE y el intento queda registrado como FALLIDO. Si lo pagado cubre el total, la reserva pasa a '
       'CONFIRMADA (RN6).')
c.code(between(TXS, 'CREATE OR REPLACE PROCEDURE sp_reservar_y_pagar (', 'END sp_reservar_y_pagar;'), size=14)
c.para('**Rollback parcial paso a paso** (sección B del script, con las consultas que lo prueban después de cada paso):')
fill_table(tbl(126), [
    [None, "pkg_turismo.sp_crear_reserva(:cli_demo, :hab_demo, DATE '2026-12-01', DATE '2026-12-04', 2, ...)",
     'La reserva PENDIENTE y su línea existen; 0 pagos'],
    [None, 'SAVEPOINT sp_reserva_creada; INSERT del anticipo (40 %); SAVEPOINT sp_anticipo_pagado',
     'Reserva + anticipo EXITOSO'],
    [None, 'INSERT del saldo con tarjeta de crédito y UPDATE de la reserva a CONFIRMADA',
     '2 pagos y la reserva CONFIRMADA (sin confirmar todavía)'],
    [None, 'ROLLBACK TO sp_anticipo_pagado;  (la tarjeta del saldo fue rechazada)',
     'Desaparecen el saldo y la confirmación; siguen la reserva PENDIENTE y el anticipo'],
    [None, 'COMMIT;', 'Queda guardada la reserva con el anticipo: pagada = N (fn_reserva_pagada)'],
])
c = Cursor(E[126].getnext())
c.para('El script prueba además el procedimiento completo: pago total (CONFIRMADA), pago rechazado (PENDIENTE + '
       'FALLIDO) y reserva solapada (ORA-20001, sin dejar nada a medias). Al final borra sus datos: es repetible.')
c.placeholder('Insertar captura del paso 3 (antes) y del paso 4 (después del ROLLBACK TO)')

c = replace_par(129)
c.para('Dos hojas de SQL Developer no compartidas (Ctrl+Shift+N) son dos sesiones de Oracle conectadas como '
       'TURISMOUQ; una tercera hoja como SYSTEM muestra los bloqueos. Scripts: `demo/concurrencia_A.sql`, '
       '`demo/concurrencia_B.sql` y `demo/concurrencia_monitor.sql`. Las dos sesiones intentan reservar la misma '
       'habitación del 20 al 23 de diciembre de 2026.')
fill_table(tbl(130), [
    ['T1', 'sp_reservar_sin_bloqueo(...) — valida con un SELECT normal e inserta; sin COMMIT', '—', 'A inserta su reserva'],
    ['T2', '—', 'sp_reservar_sin_bloqueo(...) — mismas fechas', 'B no ve la fila sin confirmar de A (lectura consistente): la habitación «parece» libre y también inserta'],
    ['T3 / T4', 'COMMIT', 'COMMIT', 'Quedan DOS reservas activas cruzadas: doble reserva'],
    ['T6', 'pkg_turismo.sp_crear_reserva(...) — SELECT ... FOR UPDATE sobre la habitación; sin COMMIT', '—', 'A bloquea la fila de la habitación'],
    ['T7', '—', 'pkg_turismo.sp_crear_reserva(...) — mismas fechas', 'B queda esperando (evento enq: TX - row lock contention; el monitor muestra que A la bloquea)'],
    ['T8', 'COMMIT', '(se desbloquea)', 'B ve la reserva de A y recibe ORA-20001: habitación no disponible. Una sola reserva'],
])
c = replace_par(132)
c.para('**Sin FOR UPDATE** la validación «consultar si está libre y luego insertar» no es atómica: entre la consulta '
       'y el COMMIT de una sesión, la otra no ve sus filas pendientes. Ni la validación del procedimiento ni el '
       'disparador de solapes pueden ver datos sin confirmar, así que las dos reservas entran. **Con '
       'SELECT ... FOR UPDATE** sobre la fila de HABITACION, la segunda sesión espera a que la primera termine; '
       'cuando la primera confirma, la segunda valida con los datos ya confirmados y es rechazada. El costo es que '
       'las reservas de una misma habitación se serializan, lo cual es justo lo que se quiere; reservas de '
       'habitaciones distintas no se bloquean entre sí.')
c.placeholder('Insertar capturas de las dos sesiones y del monitor: T2 (doble reserva) y T7 (sesión B bloqueada)')

c = replace_par(134)
c.para('`08_indices.sql` mide cada consulta antes y después con dos fuentes: `EXPLAIN PLAN` + `DBMS_XPLAN.DISPLAY` '
       '(plan y costo estimado) y la ejecución real con `GATHER_PLAN_STATISTICS` + `DBMS_XPLAN.DISPLAY_CURSOR` '
       '(filas reales, bloques leídos y tiempo). Los bloques leídos (Buffers) son la medida más estable: con 25.000 '
       'reservas las consultas tardan milisegundos y el tiempo varía con la caché. Al final, un resumen tomado de '
       'V$SQL compara costo, bloques y tiempo.')
c.bullets([
    '**Q1 — Historial de un cliente** (`WHERE cliente_id = 1500 AND estado = \'COMPLETADA\' ORDER BY fecha_checkin DESC`): RESERVA no tenía índice por su FK cliente_id. Índice **compuesto** `IX_RESERVA_CLIENTE_ESTADO (cliente_id, estado, fecha_checkin)`: igualdad en las dos primeras columnas y la tercera entrega las filas ya ordenadas.',
    '**Q2 — Llegadas de un mes por estado** (`WHERE TRUNC(fecha_checkin, \'MM\') = DATE \'2025-07-01\'`): un índice normal sobre fecha_checkin no sirve porque el filtro aplica una función. Índice **basado en función** `IX_RESERVA_MES_CHECKIN (TRUNC(fecha_checkin, \'MM\'), estado)`, que además cubre la consulta.',
    '**Q3 — Estado de cuenta de una reserva** (suma de pagos de `reserva_id = 12345`, la consulta de `fn_total_pagado`): PAGO no tenía índice por su FK. Índice **compuesto que cubre** la consulta `IX_PAGO_RESERVA (reserva_id, estado, monto)`: se resuelve sin leer la tabla.',
])
fill_table(tbl(135), [
    ['Q1 Historial de un cliente', 'IX_RESERVA_CLIENTE_ESTADO', 'Compuesto', v('q1_costo_a', 'costo'), v('q1_costo_d', 'costo'), v('q1_t_a', 'ms / bloques'), v('q1_t_d', 'ms / bloques')],
    ['Q2 Llegadas de un mes', 'IX_RESERVA_MES_CHECKIN', 'Basado en función', v('q2_costo_a', 'costo'), v('q2_costo_d', 'costo'), v('q2_t_a', 'ms / bloques'), v('q2_t_d', 'ms / bloques')],
    ['Q3 Estado de cuenta', 'IX_PAGO_RESERVA', 'Compuesto (cubre la consulta)', v('q3_costo_a', 'costo'), v('q3_costo_d', 'costo'), v('q3_t_a', 'ms / bloques'), v('q3_t_d', 'ms / bloques')],
])
c = Cursor(E[135].getnext())
c.placeholder('Insertar capturas de EXPLAIN PLAN antes y después de Q1, Q2 y Q3')

c = replace_par(138)
c.para('**Índice IX_RESERVA_ESTADO (estado) para «¿cuántas noches suman las reservas completadas?».** Con el índice '
       'creado, el optimizador sigue eligiendo TABLE ACCESS FULL; si se le obliga con el hint `INDEX`, la consulta lee '
       'más bloques que sin él. Razones técnicas:')
c.bullets([
    '**Baja selectividad.** estado tiene solo 4 valores y COMPLETADA es cerca de la mitad de las reservas. Un índice sirve para encontrar pocas filas; para traer la mitad de la tabla es más barato leerla completa.',
    '**Lectura multibloque contra lectura de un bloque.** El TABLE ACCESS FULL lee bloques contiguos, varios por cada lectura; el acceso por índice va de la hoja del índice a un bloque de la tabla por cada ROWID.',
    '**Factor de agrupamiento alto.** Las reservas COMPLETADA están repartidas por toda la tabla, así que por el índice casi cada fila obliga a visitar un bloque distinto, y el mismo bloque se visita muchas veces. USER_INDEXES.CLUSTERING_FACTOR sale cercano al número de filas y no al de bloques.',
])
c.para('Conclusión: el índice no ayuda y cuesta mantenerlo en cada INSERT y en cada cambio de estado, así que el '
       'script lo elimina. El mismo principio explica por qué antes de Q2 un índice normal sobre fecha_checkin no se '
       'usaba: la función sobre la columna impide usarlo.')
c.placeholder('Insertar captura de Q4: plan del optimizador (FULL) y plan forzado con el índice (más bloques)')

fill_table(tbl(140), [
    [None, 'Consultar habitaciones con la tarifa de hoy, la ocupación futura, clientes y reservas activas; registrar reserva y pago',
     'Vistas V_RECEPCION_* (SELECT) y EXECUTE sobre SP_RESERVAR_Y_PAGAR; ninguna tabla', 'U_RECEPCION'],
    ['Administrador de alojamiento', 'Ver sus reservas y cambiar el precio de SUS tarifas (solo la columna precio_noche)',
     'V_ADMIN_MIS_TARIFAS (SELECT, UPDATE de precio_noche) y V_ADMIN_MIS_RESERVAS; filtradas por el usuario conectado', 'U_ADMIN_ALOJ'],
    ['Gerente', 'Leer indicadores; no modifica nada',
     'MV_OCUPACION_MENSUAL, LIQUIDACION_MENSUAL, RESERVA_HISTORICO, V_GERENCIA_INGRESOS_MES (SELECT)', 'U_GERENTE'],
    ['Auditor', 'Leer quién cambió qué tarifa y cuándo; no modifica nada',
     'AUDITORIA_TARIFA y V_AUDITORIA_TARIFAS (SELECT)', 'U_AUDITOR'],
])
c = replace_par(142)
c.para('El procedimiento que usa recepción corre con los permisos de su dueño (*definer rights*): ejecutarlo no le '
       'da acceso a las tablas. El intento de recepción sobre una tabla (`11_prueba_recepcion.sql`):')
c.code("SQL> SELECT * FROM TURISMOUQ.RESERVA FETCH FIRST 5 ROWS ONLY;\n"
       "ORA-00942: la tabla o vista \"TURISMOUQ\".\"RESERVA\" no existe\n\n"
       "SQL> INSERT INTO TURISMOUQ.PAGO (reserva_id, monto, metodo, estado) VALUES (1, 1000, 'PSE', 'EXITOSO');\n"
       "ORA-00942: la tabla o vista \"TURISMOUQ\".\"PAGO\" no existe")
c.para('Oracle responde ORA-00942 y no ORA-01031 porque, para un usuario sin ningún privilegio sobre el objeto, ni '
       'siquiera confirma que la tabla existe. En cambio, las vistas sí responden, y un DELETE sobre una vista sobre '
       'la que solo tiene SELECT da ORA-01031 (privilegios insuficientes).')
c.placeholder('Insertar captura del error de U_RECEPCION sobre la tabla y de la consulta a la vista')
fill_table(tbl(143), [
    ['SESSIONS_PER_USER', '2', 'Tres hojas no compartidas de U_GERENTE: la tercera recibe ORA-02391 (15_prueba_perfil.sql, bloque A)'],
    ['IDLE_TIME', '15 minutos', 'Una sesión quieta más de 15 minutos recibe ORA-02396 en la siguiente instrucción'],
    ['FAILED_LOGIN_ATTEMPTS', '3 (bloqueo de 1 hora)', 'Tres conexiones de U_AUDITOR con clave errada: la cuenta queda LOCKED(TIMED) y el cuarto intento da ORA-28000; SYSTEM la desbloquea'],
])
c = Cursor(E[143].getnext())
c.para('El perfil `PERFIL_TURISMOUQ` limita además `CONNECT_TIME` a 480 minutos (un turno) y `PASSWORD_LIFE_TIME` a '
       '90 días. Los límites de recursos requieren `RESOURCE_LIMIT = TRUE`, que el script 09 activa.')

# ============================================================== 8. SCRIPTS
c = replace_par(146)
c.para('Repositorio: https://github.com/ValeryOrtiz/turismouq (carpeta `scripts/`). Cada script está comentado por '
       'secciones, borra al inicio lo que crea (se puede ejecutar varias veces) y corre de arriba abajo con F5.')
fill_table(tbl(147), [
    ['0', '00_usuario_y_tablespaces.sql', 'Usuario TURISMOUQ, privilegios y tablespace del histórico', 'SYSTEM'],
    ['1', '01_ddl.sql', 'Tablas, llaves y restricciones', 'TURISMOUQ'],
    ['2', '02_carga.sql', 'Datos con el volumen mínimo y asimetría', 'TURISMOUQ'],
    ['3', '03_consultas_analisis.sql', 'Las 7 consultas de la Entrega 1', 'TURISMOUQ'],
    ['4', '04_paquete.sql', 'Paquete PKG_TURISMO: función, procedimientos y cursor', 'TURISMOUQ'],
    ['5', '05_disparadores.sql', 'Auditoría de TARIFA, solapes, reseñas y temporadas', 'TURISMOUQ'],
    ['6', '06_vista_materializada.sql', 'Histórico en su tablespace y vista materializada', 'TURISMOUQ'],
    ['7', '07_transacciones.sql', 'Reserva y pago con SAVEPOINT; rollback parcial', 'TURISMOUQ'],
    ['8', '08_indices.sql', 'Índices y planes de ejecución', 'TURISMOUQ'],
    ['9', '09_seguridad.sql', 'Perfil, vistas, roles, usuarios y GRANT', 'SYSTEM'],
    ['10', '10_pruebas.sql', 'Pruebas de las Entregas 2 y 3 (repetibles)', 'TURISMOUQ'],
    ['11-14', '11_prueba_recepcion.sql … 14_prueba_auditor.sql', 'Pruebas de seguridad de cada rol', 'U_RECEPCION, U_ADMIN_ALOJ, U_GERENTE, U_AUDITOR'],
    ['15', '15_prueba_perfil.sql', 'Límites del perfil y limpieza de las pruebas de seguridad', 'SYSTEM'],
    ['—', 'demo/concurrencia_*.sql', 'Experimento de concurrencia con dos sesiones', 'TURISMOUQ (A y B) y SYSTEM (monitor)'],
])
fill_table(tbl(149), [
    [None, v('fecha_prueba', 'aa/mm/dd')],
    [None, v('quien_prueba', 'integrante')],
    [None, v('tiempo_carga', 'minutos (lo imprime 02_carga.sql)')],
    [None, v('errores_prueba', 'Ninguno / detalle')],
])

# ============================================================== 9. MANUAL
c = replace_par(152)
c.label('1. Requisitos')
c.bullets([
    'Docker Desktop y la imagen gvenzl/oracle-free (Oracle AI Database 26ai Free). También sirve Oracle XE 21c con la PDB XEPDB1.',
    'Oracle SQL Developer.',
    'Los scripts del repositorio: `git clone https://github.com/ValeryOrtiz/turismouq`.',
])
c.label('2. Base de datos')
c.code('docker run -d --name turismouq-oracle -p 1521:1521 -e ORACLE_PASSWORD=Oracle2026 \\\n'
       '       -v turismouq-data:/opt/oracle/oradata gvenzl/oracle-free\n'
       'docker logs -f turismouq-oracle      # esperar "DATABASE IS READY TO USE!"')
c.label('3. Conexión como SYSTEM')
c.para('En SQL Developer: usuario `SYSTEM`, contraseña `Oracle2026`, host `localhost`, puerto `1521` y **nombre del '
       'servicio** `FREEPDB1` (no SID). En XE 21c el servicio es `XEPDB1`. Nunca conectarse a CDB$ROOT.')
c.label('4. Usuario y tablespace')
c.para('Con la conexión SYSTEM ejecutar `00_usuario_y_tablespaces.sql` (F5). Crea el usuario `TURISMOUQ / '
       'TurismoUQ2026` y el tablespace `TS_TURISMO_HISTORICO`; el datafile queda en la carpeta de los datafiles de la '
       'PDB (en el contenedor, `/opt/oracle/oradata/FREE/FREEPDB1/`). Crear después una conexión `TURISMOUQ` con los '
       'mismos datos.')
c.label('5. Orden de los scripts')
c.bullets([
    'Como TURISMOUQ: 01, 02 (2 a 5 minutos), 03, 04, 05, 06, 07 y 08.',
    'Como SYSTEM: 09.',
    'Como TURISMOUQ: 10 (genera `10_resultado_pruebas.txt`).',
    'Opcional, pruebas de seguridad: 11 a 14 con la conexión de cada usuario (contraseñas en el README) y 15 como SYSTEM.',
])
c.label('6. Verificación')
c.bullets([
    'El final de `02_carga.sql` imprime los conteos (todos sobre el mínimo), `solapes_habitacion = 0` y el tiempo de la carga.',
    'Consulta de control: `SELECT pkg_turismo.fn_valor_estadia(1, DATE \'2026-11-28\', DATE \'2026-12-03\') FROM dual;` devuelve el valor de una estadía que cruza dos temporadas.',
    '`10_pruebas.sql` imprime OK en cada prueba, y su bloque final PF.2 compara la base con el estado inicial: todo debe decir OK.',
    '`SELECT object_name, object_type, status FROM user_objects WHERE status <> \'VALID\';` no devuelve filas.',
])

# ============================================================== 10. VIDEO
fill_table(tbl(154), [[None, v('video', 'URL del video')], [None, v('duracion', 'mm:ss')]])
set_par(156, 'Somos dos integrantes; los dos aparecen en cámara y explican su parte. Todo se ejecuta en vivo en la base '
             'cargada, desde las hojas de trabajo `demo/video_valery.sql` y `demo/video_david.sql`.')
fill_table(tbl(157), [
    [None, 'Valery Andrea Ortiz Mesa y Jhonatan David Vivas Arango', '00:00'],
    [None, 'Valery Andrea Ortiz Mesa', v('min_modelo', '00:30')],
    [None, 'Valery Andrea Ortiz Mesa', v('min_consultas', '02:30')],
    [None, 'Jhonatan David Vivas Arango', v('min_plsql', '04:30')],
    [None, 'Jhonatan David Vivas Arango (transacciones e índices) y Valery Andrea Ortiz Mesa (seguridad)', v('min_e3', '07:30')],
    [None, 'Valery Andrea Ortiz Mesa y Jhonatan David Vivas Arango', v('min_cierre', '10:30')],
])

# ============================================================== 11. APORTE
fill_table(tbl(160), [
    ['Valery Andrea Ortiz Mesa', 'MER y decisiones de diseño, DDL, generación de datos, consultas de análisis, correcciones de la Entrega 1, seguridad (roles, vistas y perfil), documento final', v('aporte_valery', '50 %')],
    ['Jhonatan David Vivas Arango', 'Paquete PL/SQL, disparadores, tablespace y vista materializada, transacciones, experimento de concurrencia e índices, pruebas', v('aporte_david', '50 %')],
])

# ============================================================== 12. CONCLUSIONES
c = replace_par(163)
c.para('**Qué aprendimos.** Que las reglas de negocio importantes no pueden quedar solo en la aplicación: los CHECK, '
       'los disparadores y los procedimientos las hacen cumplir aunque alguien escriba directo en las tablas. Que un '
       'disparador de fila que consulta su propia tabla funciona con una fila pero falla con ORA-04091 en cuanto una '
       'sentencia toca varias, y que el disparador compuesto lo resuelve. Que validar disponibilidad con un SELECT no '
       'basta cuando hay dos sesiones al tiempo: hace falta bloquear con SELECT ... FOR UPDATE. Y que un índice no '
       'siempre ayuda: con baja selectividad la lectura completa es más barata.')
c.para('**Qué fue lo más difícil.** fn_valor_estadia y sus datos: la primera carga dejaba días sin temporada, '
       'montos de pago aleatorios y reservas solapadas, y la consulta C2 descartaba ingresos. Tuvimos que regenerar '
       'los datos para que los pagos salieran de TARIFA y que ninguna habitación quedara reservada dos veces.')
c.para('**Qué cambiaríamos si empezáramos de nuevo.** Generaríamos las temporadas y los pagos con la misma regla de la '
       'función desde el primer día, agregaríamos la fecha de cancelación y el número de huéspedes en el modelo '
       'inicial, y escribiríamos las pruebas repetibles desde la Entrega 2, con su propio cliente de pruebas y una '
       'verificación final de que la base quedó igual.')

doc.core_properties.title = 'TurismoUQ - Documento final'
doc.core_properties.author = 'Valery Andrea Ortiz Mesa; Jhonatan David Vivas Arango'
doc.save(OUT)
pend = sorted(set(re.findall(r'\[\[(.*?)\]\]', '\n'.join(p.text for p in doc.paragraphs) + '\n'.join(
    cell.text for t in doc.tables for row in t.rows for cell in row.cells))))
print('Guardado:', OUT, '| marcadores pendientes:', len(pend))
