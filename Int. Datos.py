import random

registros = 30_000_000
nombre_archivo = 'datos_estudiantes.csv'

print(f"Creando {nombre_archivo}...")

try:
    
    with open(nombre_archivo, 'w', encoding='utf-8') as archivo:
        for i in range(1, registros + 1):
            
            estudiante_id = i
            nombre = f"Estudiante_{i}"
            codigo_carrera = random.randint(0, 100)
            edad = random.randint(18, 40)
            indice = random.randint(0, 10000)
            
            archivo.write(f"{estudiante_id},{nombre},{codigo_carrera},{edad},{indice}\n")
            
            if i % 1_000_000 == 0:
                print(f"Progreso: {i // 1_000_000}M / 30M")

    print("Archivo generado con exito")

except Exception as e:
    print(f"Error: {e}")