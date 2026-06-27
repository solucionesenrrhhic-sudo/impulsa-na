-- ============================================
-- IMPULSÁ N.A. - Schema Supabase
-- Ejecutar en el SQL Editor de Supabase
-- ============================================

-- Habilitar extensión UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- TABLA: tenants (los emprendedores / clientes)
-- ============================================
CREATE TABLE tenants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre TEXT NOT NULL,
  negocio TEXT,
  email TEXT UNIQUE NOT NULL,
  whatsapp TEXT,
  logo_url TEXT,
  color_primario TEXT DEFAULT '#7B1D1D',
  suscripcion_activa BOOLEAN DEFAULT TRUE,
  suscripcion_hasta DATE,
  plan TEXT DEFAULT 'mensual', -- mensual, anual
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABLA: users (usuarios de la app)
-- ============================================
CREATE TABLE usuarios (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  nombre TEXT NOT NULL,
  email TEXT NOT NULL,
  rol TEXT NOT NULL DEFAULT 'empleado', -- 'admin' (dueño) | 'empleado'
  activo BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABLA: productos (catálogo)
-- ============================================
CREATE TABLE productos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  nombre TEXT NOT NULL,
  descripcion TEXT,
  precio NUMERIC(12,2) NOT NULL DEFAULT 0,
  tipo TEXT DEFAULT 'producto', -- 'producto' | 'servicio'
  stock INTEGER DEFAULT 0,
  stock_minimo INTEGER DEFAULT 5,
  imagen_url TEXT,
  activo BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABLA: clientes
-- ============================================
CREATE TABLE clientes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  nombre TEXT NOT NULL,
  email TEXT,
  whatsapp TEXT,
  notas TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABLA: ventas
-- ============================================
CREATE TABLE ventas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  cliente_id UUID REFERENCES clientes(id) ON DELETE SET NULL,
  usuario_id UUID REFERENCES usuarios(id) ON DELETE SET NULL,
  total NUMERIC(12,2) NOT NULL DEFAULT 0,
  forma_pago TEXT DEFAULT 'efectivo', -- efectivo | transferencia | mercadopago | otro
  nota TEXT,
  estado TEXT DEFAULT 'confirmada', -- confirmada | anulada
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABLA: venta_items (detalle de cada venta)
-- ============================================
CREATE TABLE venta_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  venta_id UUID REFERENCES ventas(id) ON DELETE CASCADE,
  producto_id UUID REFERENCES productos(id) ON DELETE SET NULL,
  nombre_producto TEXT NOT NULL,
  cantidad INTEGER NOT NULL DEFAULT 1,
  precio_unitario NUMERIC(12,2) NOT NULL,
  subtotal NUMERIC(12,2) NOT NULL
);

-- ============================================
-- TABLA: catalogo_publico (tokens de catálogo compartible)
-- ============================================
CREATE TABLE catalogos_publicos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  token TEXT UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(12), 'hex'),
  titulo TEXT,
  activo BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABLA: pedidos_catalogo (pedidos recibidos del catálogo público)
-- ============================================
CREATE TABLE pedidos_catalogo (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  catalogo_id UUID REFERENCES catalogos_publicos(id),
  nombre_comprador TEXT NOT NULL,
  whatsapp_comprador TEXT,
  items JSONB NOT NULL DEFAULT '[]',
  total NUMERIC(12,2) DEFAULT 0,
  nota TEXT,
  estado TEXT DEFAULT 'pendiente', -- pendiente | visto | confirmado
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- RLS (Row Level Security)
-- ============================================
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE productos ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE ventas ENABLE ROW LEVEL SECURITY;
ALTER TABLE venta_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalogos_publicos ENABLE ROW LEVEL SECURITY;
ALTER TABLE pedidos_catalogo ENABLE ROW LEVEL SECURITY;

-- Función helper para obtener el tenant del usuario actual
CREATE OR REPLACE FUNCTION get_my_tenant_id()
RETURNS UUID AS $$
  SELECT tenant_id FROM usuarios WHERE auth_id = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER;

-- Función helper para obtener el rol del usuario actual
CREATE OR REPLACE FUNCTION get_my_role()
RETURNS TEXT AS $$
  SELECT rol FROM usuarios WHERE auth_id = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER;

-- Políticas: solo ven datos de su tenant
CREATE POLICY "tenant_productos" ON productos FOR ALL USING (tenant_id = get_my_tenant_id());
CREATE POLICY "tenant_clientes" ON clientes FOR ALL USING (tenant_id = get_my_tenant_id());
CREATE POLICY "tenant_ventas" ON ventas FOR ALL USING (tenant_id = get_my_tenant_id());
CREATE POLICY "tenant_venta_items" ON venta_items FOR ALL USING (
  venta_id IN (SELECT id FROM ventas WHERE tenant_id = get_my_tenant_id())
);
CREATE POLICY "tenant_catalogos" ON catalogos_publicos FOR ALL USING (tenant_id = get_my_tenant_id());
CREATE POLICY "tenant_pedidos" ON pedidos_catalogo FOR ALL USING (tenant_id = get_my_tenant_id());
CREATE POLICY "tenant_usuarios" ON usuarios FOR ALL USING (tenant_id = get_my_tenant_id());
CREATE POLICY "tenant_tenants" ON tenants FOR ALL USING (id = get_my_tenant_id());

-- Catálogo público: cualquiera puede leer si está activo
CREATE POLICY "public_catalogo_read" ON catalogos_publicos FOR SELECT USING (activo = TRUE);
CREATE POLICY "public_productos_read" ON productos FOR SELECT USING (activo = TRUE);
CREATE POLICY "public_pedidos_insert" ON pedidos_catalogo FOR INSERT WITH CHECK (TRUE);

-- ============================================
-- Trigger: bajar stock al confirmar venta
-- ============================================
CREATE OR REPLACE FUNCTION actualizar_stock_venta()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE productos
  SET stock = stock - NEW.cantidad
  WHERE id = NEW.producto_id AND stock > 0;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_stock_venta
AFTER INSERT ON venta_items
FOR EACH ROW EXECUTE FUNCTION actualizar_stock_venta();

-- ============================================
-- Tenant de administración (Soluciones IC)
-- ============================================
-- Insertar después de crear el primer usuario admin en Auth
-- UPDATE usuarios SET rol = 'superadmin' WHERE email = 'tu@email.com';
