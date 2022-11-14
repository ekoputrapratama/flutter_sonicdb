import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'database_generator.dart';
import 'entity_generator.dart';
import 'collection_generator.dart';

Builder generatorFactoryBuilder(BuilderOptions options) => SharedPartBuilder(
    [EntityPartGenerator(), CollectionPartGenerator(), DatabasePartGenerator()],
    "sonicdb");

Builder databaseBuilder(BuilderOptions options) =>
    LibraryBuilder(DatabaseGenerator(), generatedExtension: ".db.dart");

Builder collectionBuilder(BuilderOptions options) =>
    LibraryBuilder(CollectionGenerator(),
        generatedExtension: ".collection.dart");

Builder entityBuilder(BuilderOptions options) =>
    LibraryBuilder(EntityGenerator(), generatedExtension: ".entity.dart");

Builder sonicdbPartBuilder(BuilderOptions options) =>
    generatorFactoryBuilder(options);
