<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
    Schema::create('tables', function (Blueprint $table) {
        $table->id();

        $table->foreignId('restaurant_id')
              ->constrained('restaurants')
              ->cascadeOnDelete();

        $table->string('table_code', 64);   // e.g. F0T1, F1T5
        $table->string('floor_name', 64)->nullable(); // e.g. F0, Floor 1
        $table->enum('status', ['vacant', 'occupied'])->default('vacant');
        $table->unsignedInteger('max_seats')->nullable();

        $table->timestamps();

        // One table code must be unique per restaurant
        $table->unique(['restaurant_id', 'table_code']);
        $table->index(['restaurant_id', 'status']);
    });
}

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('tables');
    }
};
